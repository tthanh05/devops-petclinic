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
    // Switched to 8085 (host + container)
    HEALTH_URL          = 'http://localhost:8085/actuator/health'
    HEALTH_MAX_WAIT_SEC = '120'
    HEALTH_INTERVAL_SEC = '5'

    // --- Release/Production config (Octopus) ---
    DOCKER_COMPOSE_FILE_PROD = 'octopus/docker-compose.prod.yml'
    PROD_HEALTH_URL          = 'http://localhost:8086/actuator/health'
    PROD_HEALTH_MAX_WAIT_SEC = '180'
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

    /* ==================== DEPLOY (Infra-as-Code + Rollback) ==================== */
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

        // Deploy (or update) via compose
        bat "docker compose -f %DOCKER_COMPOSE_FILE% up -d --remove-orphans"

        // Health gate against host-exposed 8085
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
          bat "docker ps --format \"table {{.Names}}\\t{{.Image}}\\t{{.Status}}\\t{{.Ports}}\""
          bat "docker compose -f %DOCKER_COMPOSE_FILE% ps"
          // Robust: no error if the stack failed to start
          always {
            bat 'docker ps --format "table {{.Names}}\\t{{.Image}}\\t{{.Status}}\\t{{.Ports}}"'
            bat "docker compose -f %DOCKER_COMPOSE_FILE% ps"
            // Robust: no error if the stack failed to start
            powershell('''
              $ids = docker compose -f $env:DOCKER_COMPOSE_FILE ps -q
              if ($ids) {
                foreach ($i in $ids) {
                  docker logs --since=10m $i | Out-File -FilePath ("deploy-logs-" + $i + ".txt") -Encoding utf8
                }
              } else {
                Write-Host "No compose containers to collect logs from."
              }
            ''')
  archiveArtifacts artifacts: 'deploy-logs-*.txt', allowEmptyArchive: true
}

          archiveArtifacts artifacts: 'deploy-logs-*.txt', allowEmptyArchive: true
        }
      }
    }
  }

      /* ===================== RELEASE: Production via Octopus ===================== */
    stage('Release: Production (Octopus - tagged, versioned, env-specific)') {
      when { branch 'main' }
      steps {
        withCredentials([
          string(credentialsId: 'octopus_server', variable: 'OCTO_SERVER'),
          string(credentialsId: 'octopus_api',    variable: 'OCTO_API_KEY')
        ]) {
          // Download portable Octopus CLI (Windows) if not already present
          powershell('''
            $ErrorActionPreference = "Stop"
            $dir = Join-Path $PWD "octo-cli"; $exe = Join-Path $dir "octo.exe"
            if (-not (Test-Path $exe)) {
              New-Item -ItemType Directory -Force -Path $dir | Out-Null
              $url = "https://github.com/OctopusDeploy/OctopusCLI/releases/latest/download/OctopusTools.win-x64.zip"
              $zip = Join-Path $dir "octo.zip"
              Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing -Headers @{ "User-Agent" = "curl/8.0 jenkins" }
              Add-Type -AssemblyName System.IO.Compression.FileSystem
              [IO.Compression.ZipFile]::ExtractToDirectory($zip, $dir, $true)
            }
            "$exe" | Out-File -FilePath "octo-path.txt" -Encoding ascii
          ''')
          script { env.OCTO = readFile('octo-path.txt').trim() }

          // Pack release payload (octopus/** + Dockerfile + README*), push, create & deploy release
          bat """
            "%OCTO%" version

            "%OCTO%" pack ^
              --id="petclinic-prod" ^
              --version="%VERSION%" ^
              --format="Zip" ^
              --basePath="." ^
              --include="octopus\\**" ^
              --include="Dockerfile" ^
              --include="README*"

            "%OCTO%" push ^
              --server="%OCTO_SERVER%" ^
              --apiKey="%OCTO_API_KEY%" ^
              --package="petclinic-prod.%VERSION%.zip" ^
              --overwrite-mode=OverwriteExisting

            "%OCTO%" create-release ^
              --server="%OCTO_SERVER%" --apiKey="%OCTO_API_KEY%" ^
              --project="Petclinic" --version="%VERSION%" ^
              --package="petclinic-prod:%VERSION%" ^
              --ignoreExisting

            "%OCTO%" deploy-release ^
              --server="%OCTO_SERVER%" --apiKey="%OCTO_API_KEY%" ^
              --project="Petclinic" --version="%VERSION%" --deployTo="Production" ^
              --guidedFailure=False --progress --waitForDeployment ^
              --variable="ImageTag=%VERSION%" --variable="ServerPort=8086"
          """

          // Jenkins-side PROD health gate (PS5-safe)
          powershell('''
            $ErrorActionPreference = "Stop"
            $max = 180; $interval = 5
            if ($env:PROD_HEALTH_MAX_WAIT_SEC -and [int]::TryParse($env:PROD_HEALTH_MAX_WAIT_SEC, [ref]([int]$null))) { $max = [int]$env:PROD_HEALTH_MAX_WAIT_SEC }
            if ($env:PROD_HEALTH_INTERVAL_SEC -and [int]::TryParse($env:PROD_HEALTH_INTERVAL_SEC, [ref]([int]$null))) { $interval = [int]$env:PROD_HEALTH_INTERVAL_SEC }
            $url = $env:PROD_HEALTH_URL; $ok=$false
            Write-Host "Waiting up to $max sec for PROD health at $url ..."
            Start-Sleep -Seconds 5
            for ($t=0; $t -lt $max; $t+=$interval) {
              try {
                $r = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 5
                if ($r.StatusCode -ge 200 -and $r.StatusCode -lt 300) { "PROD Health OK (HTTP $($r.StatusCode))" | Tee-Object -FilePath health-check-prod.log -Append; $ok = $true; break }
              } catch { Start-Sleep -Seconds $interval; continue }
              Start-Sleep -Seconds $interval
            }
            if (-not $ok) {
              Write-Warning "PROD health check failed. Capturing diagnostics..."
              # Try to print compose ps from the Octopus project name we use in Deploy.ps1
              try {
                docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"
              } catch {}
              throw "Production health check failed after Octopus release."
            }
          ''')
        }

        // Tag the release in Git (proves 'tagged + versioned' promotion)
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
          archiveArtifacts artifacts: 'octo-cli/**, octo-path.txt, health-check-prod.log, petclinic-prod.*.zip', fingerprint: true, allowEmptyArchive: true
        }
        failure {
          echo "Production release failed (Octopus or health gate). Check logs/artifacts."
          archiveArtifacts artifacts: 'octo-cli/**, octo-path.txt, petclinic-prod.*.zip', allowEmptyArchive: true
        }
      }
    }


  post {
    success {
      echo "Build ${VERSION} passed all gates and deployed to staging on 8085."
    }
    failure {
      echo "Build ${VERSION} failed. If failure is in Tag/Deploy, check credentials/Docker/health gate."
    }
  }
}
