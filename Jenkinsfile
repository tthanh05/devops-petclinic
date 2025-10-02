pipeline {
  agent any

  tools { jdk 'jdk17' }

  options {
    timestamps()
    buildDiscarder(logRotator(numToKeepStr: '20'))
  }

  environment {
    MVN = 'mvnw.cmd -B -V --no-transfer-progress -Dmaven.repo.local=.m2\\repo'
    APP_NAME = 'spring-petclinic'
    GIT_SHA  = "${env.GIT_COMMIT?.take(7) ?: 'local'}"
    VERSION  = "${env.BUILD_NUMBER}-${GIT_SHA}"
    DC_CACHE = '.dc'

    // --- Deploy/Staging config ---
    DOCKER_COMPOSE_FILE = 'docker-compose.staging.yml'
    STAGING_IMAGE_TAG   = 'staging'      // moving tag used by compose
    PREV_IMAGE_TAG      = 'staging-prev' // rollback tag
    HEALTH_URL          = 'http://localhost:8085/actuator/health'
    HEALTH_MAX_WAIT_SEC = '120'
    HEALTH_INTERVAL_SEC = '5'

    // --- Release/Production config (environment-specific) ---
    DOCKER_COMPOSE_FILE_PROD = 'docker-compose.prod.yml'
    PROD_IMAGE_TAG           = 'prod'        // moving tag used by prod compose
    PROD_PREV_IMAGE_TAG      = 'prod-prev'   // rollback tag for prod
    PROD_HEALTH_URL          = 'http://localhost:8086/actuator/health'
    PROD_HEALTH_MAX_WAIT_SEC = '150'
    PROD_HEALTH_INTERVAL_SEC = '5'
  }

  stages {
    stage('Checkout') {
      steps { checkout scm }
    }

    stage('Build') {
      steps {
        bat '"%JAVA_HOME%\\bin\\java" -version'
        bat "${MVN} spring-javaformat:apply"
        bat "${MVN} -DskipTests -Dcheckstyle.skip=true clean package"
      }
      post {
        success {
          archiveArtifacts artifacts: 'target\\*.jar', fingerprint: true
        }
      }
    }

    stage('Test: Unit') {
      steps {
        bat "${MVN} -Dcheckstyle.skip=true -DskipITs=true test"
      }
      post {
        always {
          junit testResults: 'target/surefire-reports/*.xml',
                keepLongStdio: true,
                allowEmptyResults: false
        }
      }
    }

    stage('Test: Integration') {
      steps {
        bat "${MVN} -Dcheckstyle.skip=true -DskipITs=false -Djacoco.append=true failsafe:integration-test failsafe:verify"
      }
      post {
        always {
          junit testResults: 'target/failsafe-reports/*.xml',
                keepLongStdio: true,
                allowEmptyResults: false
        }
      }
    }

    /* -------------------- SECURITY (SCA) -------------------- */
    stage('Security: Dependency Scan (OWASP)') {
      steps {
        bat """
          ${MVN} -DskipTests=true ^
                 org.owasp:dependency-check-maven:check ^
                 -DdataDirectory=%DC_CACHE% ^
                 -Dformat=ALL ^
                 -DfailBuildOnCVSS=7 ^
                 -Danalyzers.assembly.enabled=false ^
                 -DautoUpdate=true
        """
      }
      post {
        always {
          archiveArtifacts artifacts: '''
            target/dependency-check-report.html,
            target/dependency-check-report.xml,
            target/dependency-check-report.json,
            target/dependency-check-junit.xml
          '''.trim().replaceAll("\\s+", " "), fingerprint: true, allowEmptyArchive: true

          publishHTML(target: [
            reportDir: 'target',
            reportFiles: 'dependency-check-report.html',
            reportName: 'OWASP Dependency-Check',
            keepAll: true,
            allowMissing: false,
            alwaysLinkToLastBuild: false
          ])
          archiveArtifacts artifacts: 'target/dependency-check-report/**, target/dependency-check-json*', allowEmptyArchive: true
          junit testResults: 'target/dependency-check-junit.xml', allowEmptyResults: true
        }
        failure {
          echo 'High severity CVEs detected (CVSS >= 7).'
        }
        unsuccessful {
          echo 'Review Dependency-Check results; only suppress genuine false positives.'
        }
      }
    }

    /* -------------------- CODE QUALITY (SonarQube) -------------------- */
    stage('Code Quality: SonarQube') {
      steps {
        bat "${MVN} -Dcheckstyle.skip=true jacoco:report"

        withSonarQubeEnv('sonarqube-server') {
          withCredentials([string(credentialsId: 'sonar-token', variable: 'SONAR_TOKEN')]) {
            bat """
              ${MVN} -DskipTests=true ^
                     -Dsonar.login=%SONAR_TOKEN% ^
                     -Dsonar.working.directory=.scannerwork ^
                     -Dsonar.projectVersion=%BUILD_NUMBER% ^
                     sonar:sonar
            """
            bat 'type .scannerwork\\report-task.txt'
          }
        }
        archiveArtifacts artifacts: '.scannerwork/**', fingerprint: false, allowEmptyArchive: true
      }
    }

    stage('Quality Gate') {
      steps {
        timeout(time: 10, unit: 'MINUTES') {
          waitForQualityGate abortPipeline: true
        }
      }
    }

    stage('Coverage Report') {
      steps {
        bat "${MVN} -Dcheckstyle.skip=true jacoco:report"
        publishHTML(target: [
          reportDir: 'target/site/jacoco',
          reportFiles: 'index.html',
          reportName: 'JaCoCo Coverage',
          keepAll: true,
          allowMissing: false,
          alwaysLinkToLastBuild: false
        ])
      }
    }

    stage('Tag Build') {
      when { branch 'main' }
      steps {
        withCredentials([usernamePassword(credentialsId: 'github_push', usernameVariable: 'GIT_USER', passwordVariable: 'GIT_PASS')]) {
          bat '''
            git config user.email "ci@jenkins"
            git config user.name  "Jenkins CI"
            git remote set-url origin https://%GIT_USER%:%GIT_PASS%@github.com/tthanh05/devops-petclinic.git
            git tag -a v%BUILD_NUMBER%-%GIT_SHA% -m "CI build %BUILD_NUMBER% (%GIT_SHA%)"
            git push origin --tags
          '''
        }
      }
    }

    /* ==================== DEPLOY (Staging) ==================== */
    stage('Deploy: Staging (Docker Compose on 8085 with Health Gate + Rollback)') {
      steps {
        bat 'docker --version'
        bat 'docker compose version'

        bat """
          REM --- Preserve previous staging image for rollback (if it exists)
          for /f "tokens=*" %%i in ('docker images -q %APP_NAME%:%STAGING_IMAGE_TAG%') do (
            docker image tag %APP_NAME%:%STAGING_IMAGE_TAG% %APP_NAME%:%PREV_IMAGE_TAG%
          )
          REM --- Build new versioned image and retag to 'staging'
          docker build -t %APP_NAME%:%VERSION% -f Dockerfile .
          docker image tag %APP_NAME%:%VERSION% %APP_NAME%:%STAGING_IMAGE_TAG%
        """

        bat "docker compose -f %DOCKER_COMPOSE_FILE% up -d --remove-orphans"

        powershell('''
          $max = [int]$env:HEALTH_MAX_WAIT_SEC
          $interval = [int]$env:HEALTH_INTERVAL_SEC
          $ok = $false
          Write-Host "Waiting up to $max sec for health at $($env:HEALTH_URL) ..."
          for ($t = 0; $t -lt $max; $t += $interval) {
            try {
              $resp = Invoke-WebRequest -Uri $env:HEALTH_URL -UseBasicParsing -TimeoutSec 5
              if ($resp.StatusCode -ge 200 -and $resp.StatusCode -lt 300) {
                Write-Host "Health OK (HTTP $($resp.StatusCode))"
                $ok = $true; break
              }
            } catch {
              Start-Sleep -Seconds $interval
              continue
            }
            Start-Sleep -Seconds $interval
          }
          if (-not $ok) {
            Write-Host "Health check FAILED. Rolling back to previous image tag..."
            docker image tag $env:APP_NAME:$env:PREV_IMAGE_TAG $env:APP_NAME:$env:STAGING_IMAGE_TAG
            docker compose -f $env:DOCKER_COMPOSE_FILE up -d --remove-orphans
            throw "Deploy failed health gate; rolled back to previous image."
          }
          "Health OK" | Tee-Object -FilePath health-check.log -Append
        ''')
      }
      post {
        success {
          echo "Staging healthy at ${HEALTH_URL}. Image: ${APP_NAME}:${VERSION} (tag=${STAGING_IMAGE_TAG})."
          archiveArtifacts artifacts: "${DOCKER_COMPOSE_FILE}", fingerprint: true, allowEmptyArchive: false
        }
        failure {
          echo "Deploy failed; rollback attempted via tag ${PREV_IMAGE_TAG}."
        }
        always {
          powershell('''
            Set-StrictMode -Version Latest
            try { docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}" | Out-File -FilePath "docker-ps.txt" -Encoding utf8 } catch { "docker ps failed: $($_.Exception.Message)" | Out-File -FilePath "docker-ps.txt" -Encoding utf8 }
            try { docker compose -f "$env:DOCKER_COMPOSE_FILE" ps | Out-File -FilePath "compose-ps.txt" -Encoding utf8 } catch { "docker compose ps failed: $($_.Exception.Message)" | Out-File -FilePath "compose-ps.txt" -Encoding utf8 }
            foreach ($n in @("petclinic-app","petclinic-db")) {
              try { docker logs --since=15m $n | Out-File -FilePath ("deploy-logs-" + $n + ".txt") -Encoding utf8 } catch { ("no logs available for " + $n + ": " + $($_.Exception.Message)) | Out-File -FilePath ("deploy-logs-" + $n + ".txt") -Encoding utf8 }
            }
          ''')
          archiveArtifacts artifacts: 'docker-ps.txt, compose-ps.txt, deploy-logs-*.txt, health-check.log', allowEmptyArchive: true
        }
      }
    }

    /* ==================== RELEASE (Production) ==================== */
    stage('Release: Production (Compose on 8086, Env Config, Health Gate + Rollback + Git Release Tag)') {
      when { branch 'main' }  // only release from main
      steps {
        bat 'docker --version'
        bat 'docker compose version'

        // Promote the exact tested VERSION into prod: keep prod-prev for rollback
        bat """
          REM --- Preserve previous prod image for rollback (if exists)
          for /f "tokens=*" %%i in ('docker images -q %APP_NAME%:%PROD_IMAGE_TAG%') do (
            docker image tag %APP_NAME%:%PROD_IMAGE_TAG% %APP_NAME%:%PROD_PREV_IMAGE_TAG%
          )
          REM --- Move prod tag to the immutable VERSION we built earlier
          docker image tag %APP_NAME%:%VERSION% %APP_NAME%:%PROD_IMAGE_TAG%
        """

        // Bring up production stack with env-specific settings
        bat "docker compose -f %DOCKER_COMPOSE_FILE_PROD% up -d --remove-orphans"

        // Health gate for PROD
        powershell('''
          $max = [int]$env:PROD_HEALTH_MAX_WAIT_SEC
          $interval = [int]$env:PROD_HEALTH_INTERVAL_SEC
          $ok = $false
          Write-Host "Waiting up to $max sec for PROD health at $($env:PROD_HEALTH_URL) ..."
          for ($t = 0; $t -lt $max; $t += $interval) {
            try {
              $resp = Invoke-WebRequest -Uri $env:PROD_HEALTH_URL -UseBasicParsing -TimeoutSec 5
              if ($resp.StatusCode -ge 200 -and $resp.StatusCode -lt 300) {
                Write-Host "PROD Health OK (HTTP $($resp.StatusCode))"
                $ok = $true; break
              }
            } catch {
              Start-Sleep -Seconds $interval
              continue
            }
            Start-Sleep -Seconds $interval
          }
          if (-not $ok) {
            Write-Host "PROD health FAILED. Rolling back to previous prod image tag..."
            docker image tag $env:APP_NAME:$env:PROD_PREV_IMAGE_TAG $env:APP_NAME:$env:PROD_IMAGE_TAG
            docker compose -f $env:DOCKER_COMPOSE_FILE_PROD up -d --remove-orphans
            throw "Release failed health gate; rolled back to previous prod image."
          }
          "PROD Health OK" | Tee-Object -FilePath health-check-prod.log -Append
        ''')

        // Create an annotated Git tag for the production release
        withCredentials([usernamePassword(credentialsId: 'github_push', usernameVariable: 'GIT_USER', passwordVariable: 'GIT_PASS')]) {
          bat '''
            git config user.email "ci@jenkins"
            git config user.name  "Jenkins CI"
            git remote set-url origin https://%GIT_USER%:%GIT_PASS%@github.com/tthanh05/devops-petclinic.git
            git tag -a release-v%BUILD_NUMBER%-%GIT_SHA%-prod -m "Production release %BUILD_NUMBER% (%GIT_SHA%)"
            git push origin --tags
          '''
        }
      }
      post {
        success {
          echo "Production healthy at ${PROD_HEALTH_URL}. Image: ${APP_NAME}:${VERSION} (tag=${PROD_IMAGE_TAG}). Release tag pushed."
          archiveArtifacts artifacts: "${DOCKER_COMPOSE_FILE_PROD}", fingerprint: true, allowEmptyArchive: false
        }
        failure {
          echo "Production release failed; rollback attempted using tag ${PROD_PREV_IMAGE_TAG}."
        }
        always {
          powershell('''
            Set-StrictMode -Version Latest
            try { docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}" | Out-File -FilePath "docker-ps-prod.txt" -Encoding utf8 } catch { "docker ps failed: $($_.Exception.Message)" | Out-File -FilePath "docker-ps-prod.txt" -Encoding utf8 }
            try { docker compose -f "$env:DOCKER_COMPOSE_FILE_PROD" ps | Out-File -FilePath "compose-ps-prod.txt" -Encoding utf8 } catch { "docker compose ps failed: $($_.Exception.Message)" | Out-File -FilePath "compose-ps-prod.txt" -Encoding utf8 }
            foreach ($n in @("petclinic-app-prod","petclinic-db-prod")) {
              try { docker logs --since=15m $n | Out-File -FilePath ("release-logs-" + $n + ".txt") -Encoding utf8 } catch { ("no logs for " + $n + ": " + $($_.Exception.Message)) | Out-File -FilePath ("release-logs-" + $n + ".txt") -Encoding utf8 }
            }
          ''')
          archiveArtifacts artifacts: 'docker-ps-prod.txt, compose-ps-prod.txt, release-logs-*.txt, health-check-prod.log', allowEmptyArchive: true
        }
      }
    }
  }

  post {
    success { echo "Build ${VERSION} passed all gates, deployed to staging (8085), and production (8086) released healthy." }
    failure { echo "Build ${VERSION} failed. If failure is in Tag/Deploy/Release, check credentials/Docker/health gate." }
  }
}
