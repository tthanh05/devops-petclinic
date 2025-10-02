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

    // ---- Staging (Compose) ----
    DOCKER_COMPOSE_FILE = 'docker-compose.staging.yml'
    STAGING_IMAGE_TAG   = 'staging'
    PREV_IMAGE_TAG      = 'staging-prev'
    HEALTH_URL          = 'http://localhost:8085/actuator/health'
    HEALTH_MAX_WAIT_SEC = '120'
    HEALTH_INTERVAL_SEC = '5'

    // ---- Production (Octopus) ----
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
      post { always { junit testResults: 'target/surefire-reports/*.xml', keepLongStdio: true } }
    }

    stage('Test: Integration') {
      steps { bat "${MVN} -Dcheckstyle.skip=true -DskipITs=false -Djacoco.append=true failsafe:integration-test failsafe:verify" }
      post { always { junit testResults: 'target/failsafe-reports/*.xml', keepLongStdio: true } }
    }

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
          archiveArtifacts artifacts: 'target/dependency-check-report.* , target/dependency-check-junit.xml', allowEmptyArchive: true
          publishHTML(target: [reportDir: 'target', reportFiles: 'dependency-check-report.html', reportName: 'OWASP Dependency-Check'])
          junit testResults: 'target/dependency-check-junit.xml', allowEmptyResults: true
        }
      }
    }

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
        archiveArtifacts artifacts: '.scannerwork/**', allowEmptyArchive: true
      }
    }

    stage('Quality Gate') {
      steps { timeout(time: 10, unit: 'MINUTES') { waitForQualityGate abortPipeline: true } }
    }

    stage('Coverage Report') {
      steps {
        bat "${MVN} -Dcheckstyle.skip=true jacoco:report"
        publishHTML(target: [reportDir: 'target/site/jacoco', reportFiles: 'index.html', reportName: 'JaCoCo Coverage'])
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

    // Deploy stage: Compose + Health gate + Rollback
    stage('Deploy: Staging (Compose 8085 + Health + Rollback)') {
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
          $max = [int]$env:HEALTH_MAX_WAIT_SEC
          $int = [int]$env:HEALTH_INTERVAL_SEC
          $ok = $false
          Write-Host "Waiting up to $max sec for health at $($env:HEALTH_URL) ..."
          for ($t=0; $t -lt $max; $t += $int) {
            try {
              $r = Invoke-WebRequest -Uri $env:HEALTH_URL -UseBasicParsing -TimeoutSec 5
              if ($r.StatusCode -ge 200 -and $r.StatusCode -lt 300) { "Health OK (HTTP $($r.StatusCode))" | Tee-Object -FilePath health-check.log -Append; $ok = $true; break }
            } catch { Start-Sleep -Seconds $int; continue }
            Start-Sleep -Seconds $int
          }
          if (-not $ok) {
            Write-Host "Health check FAILED. Rolling back..."
            docker image tag $env:APP_NAME:$env:PREV_IMAGE_TAG $env:APP_NAME:$env:STAGING_IMAGE_TAG
            docker compose -f $env:DOCKER_COMPOSE_FILE up -d --remove-orphans
            throw "Deploy failed health gate; rolled back to previous image."
          }
        ''')
      }
      post {
        success {
          echo "Staging healthy at ${HEALTH_URL}. Image=${APP_NAME}:${VERSION} (tag=${STAGING_IMAGE_TAG})."
          archiveArtifacts artifacts: "${DOCKER_COMPOSE_FILE}, health-check.log", fingerprint: true, allowEmptyArchive: true
        }
        always {
          powershell('''
            try { docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}" | Out-File docker-ps.txt -Encoding utf8 } catch {}
            try { docker compose -f "$env:DOCKER_COMPOSE_FILE" ps | Out-File compose-ps.txt -Encoding utf8 } catch {}
          ''')
          archiveArtifacts artifacts: 'docker-ps.txt, compose-ps.txt', allowEmptyArchive: true
        }
      }
    }

    // ================= RELEASE: Octopus (automated, env-specific) =================
    stage('Release: Production (Octopus — tagged, versioned, env-specific)') {
      when { branch 'main' }   // release only from main
      steps {
        withCredentials([
          string(credentialsId: 'octopus_server', variable: 'OCTO_SERVER'),
          string(credentialsId: 'octopus_api',    variable: 'OCTO_API_KEY')
        ]) {
    
          // 1) Ensure Octopus CLI is available (portable in workspace)
          powershell('''
            $ErrorActionPreference = "Stop"
            $cliDir = Join-Path $PWD "octo-cli"
            $octo   = Join-Path $cliDir "octo.exe"
            if (-not (Test-Path $octo)) {
              New-Item -ItemType Directory -Force -Path $cliDir | Out-Null
              $urls = @(
                "https://download.octopus.com/octopus-tools/9.4.7/OctopusTools.9.4.7.win-x64.zip",
                "https://github.com/OctopusDeploy/OctopusCLI/releases/latest/download/OctopusTools.win-x64.zip"
              )
              $ok = $false
              foreach ($u in $urls) {
                try {
                  $zip = Join-Path $cliDir "octo.zip"
                  Invoke-WebRequest -Uri $u -OutFile $zip -UseBasicParsing -Headers @{ "User-Agent" = "curl/8.0 jenkins" }
                  Add-Type -AssemblyName System.IO.Compression.FileSystem
                  [IO.Compression.ZipFile]::ExtractToDirectory($zip, $cliDir, $true)
                  if (Test-Path $octo) { $ok = $true; break }
                } catch {
                  Write-Warning "Octopus CLI download failed from $u : $($_.Exception.Message)"
                }
              }
              if (-not $ok) { throw "Could not download Octopus CLI." }
            }
            "$octo" | Out-File -FilePath "octo-path.txt" -Encoding ascii
          ''')
    
          script { env.OCTO = readFile('octo-path.txt').trim() }
    
          // 2) Pack the release assets WITH the octopus/ folder (use Octopus CLI pack)
          bat """
            "%OCTO%" version
    
            REM Build petclinic-prod.%VERSION%.zip, keeping the octopus\\ folder
            "%OCTO%" pack ^
              --id="petclinic-prod" ^
              --version="%VERSION%" ^
              --format="Zip" ^
              --basePath="." ^
              --include="docker-compose.prod.yml" ^
              --include="octopus\\**"
    
            REM 3) Push package to Octopus built-in feed
            "%OCTO%" push ^
              --server="%OCTO_SERVER%" ^
              --apiKey="%OCTO_API_KEY%" ^
              --package="petclinic-prod.%VERSION%.zip" ^
              --overwrite-mode=OverwriteExisting
    
            REM 4) Create (or reuse) the release
            "%OCTO%" create-release ^
            --server="%OCTO_SERVER%" --apiKey="%OCTO_API_KEY%" ^
            --project="Petclinic" --version="%VERSION%" ^
            --package="petclinic-prod:%VERSION%" ^
            --ignoreExisting

    
            REM 5) Deploy the release to Production with env-specific vars
            "%OCTO%" deploy-release ^
              --server="%OCTO_SERVER%" ^
              --apiKey="%OCTO_API_KEY%" ^
              --project="Petclinic" ^
              --version="%VERSION%" ^
              --deployTo="Production" ^
              --guidedFailure=False ^
              --progress ^
              --waitForDeployment ^
              --variable="ImageTag=%VERSION%" ^
              --variable="ServerPort=8086"
          """
    
          // 6) Independent prod health gate (Jenkins verifies /actuator/health)
          powershell('''
            $max = [int]$env:PROD_HEALTH_MAX_WAIT_SEC
            $int = [int]$env:PROD_HEALTH_INTERVAL_SEC
            $ok = $false
            Write-Host "Waiting up to $max sec for PROD health at $($env:PROD_HEALTH_URL) ..."
            for ($t=0; $t -lt $max; $t+=$int) {
              try {
                $r = Invoke-WebRequest -Uri $env:PROD_HEALTH_URL -UseBasicParsing -TimeoutSec 5
                if ($r.StatusCode -ge 200 -and $r.StatusCode -lt 300) {
                  "PROD Health OK (HTTP $($r.StatusCode))" | Tee-Object -FilePath health-check-prod.log -Append
                  $ok = $true; break
                }
              } catch {
                Start-Sleep -Seconds $int
                continue
              }
              Start-Sleep -Seconds $int
            }
            if (-not $ok) { throw "Production health check failed after Octopus release." }
          ''')
    
          // 7) Git tag the production release
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
      }
      post {
        success {
          echo "Production released via Octopus. ${PROD_HEALTH_URL} healthy. Version=${VERSION}."
          archiveArtifacts artifacts: 'octo-cli/**, octo-path.txt, health-check-prod.log, petclinic-prod.*.zip',
                            allowEmptyArchive: true, fingerprint: true
        }
        failure {
          echo "Production release failed (Octopus or health gate). Check logs/artifacts."
          archiveArtifacts artifacts: 'octo-cli/**, octo-path.txt, petclinic-prod.*.zip',
                            allowEmptyArchive: true
        }
      }
    }

  }

  post {
    success {
      echo "Build ${VERSION} passed all gates; staging (8085) deployed and production released via Octopus (8086)."
    }
    failure {
      echo "Build ${VERSION} failed. If failure is in Tag/Deploy/Release, check credentials, Octopus CLI, or health gate."
    }
  }
}
