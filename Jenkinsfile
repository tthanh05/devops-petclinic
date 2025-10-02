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
    STAGING_IMAGE_TAG   = 'staging'
    PREV_IMAGE_TAG      = 'staging-prev'
    HEALTH_URL          = 'http://localhost:8085/actuator/health'
    HEALTH_MAX_WAIT_SEC = '120'
    HEALTH_INTERVAL_SEC = '5'

    // --- Release/Production config (Octopus) ---
    DOCKER_COMPOSE_FILE_PROD = 'docker-compose.prod.yml'
    PROD_HEALTH_URL          = 'http://localhost:8086/actuator/health'
    PROD_HEALTH_MAX_WAIT_SEC = '150'
    PROD_HEALTH_INTERVAL_SEC = '5'
  }

  stages {
    stage('Checkout') { steps { checkout scm } }

    stage('Build') {
      steps {
        bat '"%JAVA_HOME%\\bin\\java" -version'
        bat "${MVN} spring-javaformat:apply"
        bat "${MVN} -DskipTests -Dcheckstyle.skip=true clean package"
      }
      post { success { archiveArtifacts artifacts: 'target\\*.jar', fingerprint: true } }
    }

    stage('Test: Unit') {
      steps { bat "${MVN} -Dcheckstyle.skip=true -DskipITs=true test" }
      post {
        always {
          junit testResults: 'target/surefire-reports/*.xml', keepLongStdio: true, allowEmptyResults: false
        }
      }
    }

    stage('Test: Integration') {
      steps {
        bat "${MVN} -Dcheckstyle.skip=true -DskipITs=false -Djacoco.append=true failsafe:integration-test failsafe:verify"
      }
      post {
        always {
          junit testResults: 'target/failsafe-reports/*.xml', keepLongStdio: true, allowEmptyResults: false
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
        failure { echo 'High severity CVEs detected (CVSS >= 7).' }
        unsuccessful { echo 'Review Dependency-Check results; only suppress genuine false positives.' }
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
      steps { timeout(time: 10, unit: 'MINUTES') { waitForQualityGate abortPipeline: true } }
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

    /* ==================== DEPLOY (Staging with health + rollback) ==================== */
    stage('Deploy: Staging (Docker Compose on 8085 with Health Gate + Rollback)') {
      steps {
        bat 'docker --version'
        bat 'docker compose version'

        bat """
          for /f "tokens=*" %%i in ('docker images -q %APP_NAME%:%STAGING_IMAGE_TAG%') do (
            docker image tag %APP_NAME%:%STAGING_IMAGE_TAG% %APP_NAME%:%PREV_IMAGE_TAG%
          )
          docker build -t %APP_NAME%:%VERSION% -f Dockerfile .
          docker image tag %APP_NAME%:%VERSION% %APP_NAME%:%STAGING_IMAGE_TAG%
        """
        bat "docker compose -f %DOCKER_COMPOSE_FILE% up -d --remove-orphans"

        powershell('''
          $max = [int]$env:HEALTH_MAX_WAIT_SEC; $interval = [int]$env:HEALTH_INTERVAL_SEC; $ok = $false
          Write-Host "Waiting up to $max sec for health at $($env:HEALTH_URL) ..."
          for ($t = 0; $t -lt $max; $t += $interval) {
            try {
              $resp = Invoke-WebRequest -Uri $env:HEALTH_URL -UseBasicParsing -TimeoutSec 5
              if ($resp.StatusCode -ge 200 -and $resp.StatusCode -lt 300) { Write-Host "Health OK (HTTP $($resp.StatusCode))"; $ok = $true; break }
            } catch { Start-Sleep -Seconds $interval; continue }
            Start-Sleep -Seconds $interval
          }
          if (-not $ok) {
            Write-Host "Health check FAILED. Rolling back..."
            docker image tag $env:APP_NAME:$env:PREV_IMAGE_TAG $env:APP_NAME:$env:STAGING_IMAGE_TAG
            docker compose -f $env:DOCKER_COMPOSE_FILE up -d --remove-orphans
            throw "Deploy failed health gate; rolled back."
          }
          "Health OK" | Tee-Object -FilePath health-check.log -Append
        ''')
      }
      post {
        success {
          echo "Staging healthy at ${HEALTH_URL}. Image: ${APP_NAME}:${VERSION} (tag=staging)."
          archiveArtifacts artifacts: "${DOCKER_COMPOSE_FILE}", fingerprint: true, allowEmptyArchive: false
        }
        failure { echo "Deploy failed; rollback attempted." }
        always {
          powershell('''
            try { docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}" | Out-File docker-ps.txt -Encoding utf8 } catch { "ps failed: $($_.Exception.Message)" | Out-File docker-ps.txt }
            try { docker compose -f "$env:DOCKER_COMPOSE_FILE" ps | Out-File compose-ps.txt -Encoding utf8 } catch { "compose ps failed: $($_.Exception.Message)" | Out-File compose-ps.txt }
          ''')
          archiveArtifacts artifacts: 'docker-ps.txt, compose-ps.txt, health-check.log', allowEmptyArchive: true
        }
      }
    }

    /* ==================== RELEASE (Production via Octopus Deploy) ==================== */
    stage('Release: Production (Octopus - tagged, versioned, env-specific)') {
      when { branch 'main' } // release only from main
      steps {
        withCredentials([
          string(credentialsId: 'octopus_server', variable: 'OCTO_SERVER'),
          string(credentialsId: 'octopus_api',    variable: 'OCTO_API_KEY')
        ]) {
          // 1) Pack release assets locally (no Docker mount needed)
          powershell('''
            $ErrorActionPreference = "Stop"
            $pkg = "petclinic-prod.$env:VERSION.zip"
            if (Test-Path $pkg) { Remove-Item -Force $pkg }
            $paths = @(
              "docker-compose.prod.yml",
              "octopus\\Deploy.ps1"
            )
            foreach ($p in $paths) {
              if (-not (Test-Path $p)) { throw "Missing file: $p" }
            }
            Compress-Archive -Path $paths -DestinationPath $pkg -Force
            Write-Host "Packaged: $pkg"
          ''')
    
          // 2) Push package to Octopus Built-in feed via REST (no CLI, no mounts)
          powershell('''
            $ErrorActionPreference = "Stop"
            $pkg = "petclinic-prod.$env:VERSION.zip"
            $uri = ($env:OCTO_SERVER.TrimEnd('/')) + "/api/packages/raw?replace=true"
            $headers = @{ "X-Octopus-ApiKey" = $env:OCTO_API_KEY }
            Write-Host "Uploading $pkg to $uri ..."
            Invoke-WebRequest -Method Post -Uri $uri -Headers $headers `
              -InFile $pkg -ContentType "application/octet-stream" | Out-Null
            Write-Host "Upload OK."
          ''')
    
          // 3) Create (or reuse) the release for project Petclinic using Octopus CLI in Docker (no -v)
          bat '''
            docker pull octopusdeploy/octo:latest
    
            docker run --rm octopusdeploy/octo:latest ^
              create-release --server=%OCTO_SERVER% --apiKey=%OCTO_API_KEY% ^
              --project="Petclinic" --version=%VERSION% --packageVersion=%VERSION% --ignoreExisting
          '''
    
          // 4) Deploy to Production with env-specific variables; hard timeout; guidedFailure off
          timeout(time: 20, unit: 'MINUTES') {
            bat '''
              docker run --rm octopusdeploy/octo:latest ^
                deploy-release --server=%OCTO_SERVER% --apiKey=%OCTO_API_KEY% ^
                --project="Petclinic" --version=%VERSION% --deployTo="Production" ^
                --progress --waitForDeployment --guidedFailure=False ^
                --deploymentTimeout="00:15:00" --cancelOnTimeout ^
                --variable="ImageTag=%VERSION%" --variable="ServerPort=8086"
            '''
          }
        }
    
        // 5) Jenkins-side PROD health check
        powershell('''
          $max = [int]$env:PROD_HEALTH_MAX_WAIT_SEC; $interval = [int]$env:PROD_HEALTH_INTERVAL_SEC; $ok = $false
          Write-Host "Waiting up to $max sec for PROD health at $($env:PROD_HEALTH_URL) ..."
          for ($t = 0; $t -lt $max; $t += $interval) {
            try {
              $resp = Invoke-WebRequest -Uri $env:PROD_HEALTH_URL -UseBasicParsing -TimeoutSec 5
              if ($resp.StatusCode -ge 200 -and $resp.StatusCode -lt 300) { Write-Host "PROD Health OK (HTTP $($resp.StatusCode))"; $ok = $true; break }
            } catch { Start-Sleep -Seconds $interval; continue }
            Start-Sleep -Seconds $interval
          }
          if (-not $ok) { throw "Production health check failed after Octopus release." }
          "PROD Health OK" | Tee-Object -FilePath health-check-prod.log -Append
        ''')
    
        // 6) Annotated Git tag for the production release
        withCredentials([usernamePassword(credentialsId: 'github_push', usernameVariable: 'GIT_USER', passwordVariable: 'GIT_PASS')]) {
          bat '''
            git config user.email "ci@jenkins"
            git config user.name  "Jenkins CI"
            git remote set-url origin https://%GIT_USER%:%GIT_PASS%@github.com/tthanh05/devops-petclinic.git
            git tag -a release-v%BUILD_NUMBER%-%GIT_SHA%-octopus -m "Production release via Octopus: %BUILD_NUMBER% (%GIT_SHA%)"
            git push origin --tags
          '''
        }
      }
      post {
        success {
          echo "Production released via Octopus. ${PROD_HEALTH_URL} healthy. Version=${VERSION}."
          archiveArtifacts artifacts: "${DOCKER_COMPOSE_FILE_PROD}, health-check-prod.log", fingerprint: true, allowEmptyArchive: true
        }
        failure { echo "Production release failed (Octopus or health gate). Check logs/artifacts." }
      }
    }

  }

  post {
    success {
      echo "Build ${VERSION} passed gates; staging (8085) deployed and production released via Octopus (8086)."
    }
    failure {
      echo "Build ${VERSION} failed. If failure is in Tag/Deploy/Release, check credentials, Octopus CLI, or health gate."
    }
  }
}
