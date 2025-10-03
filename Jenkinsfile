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
    AWS_DEFAULT_REGION = 'ap-southeast-2'
    S3_BUCKET          = 'petclinic-codedeploy-tthanh-ap-southeast-2'
    COMPOSE_PROJECT_NAME = 'petclinic-ci'
    STAGING_PORT         = '8085'

    // --- Deploy/Staging config ---
    DOCKER_COMPOSE_FILE = 'docker-compose.staging.yml'
    STAGING_IMAGE_TAG   = 'staging'      // moving tag used by compose
    PREV_IMAGE_TAG      = 'staging-prev' // rollback tag
    // Switched to 8085 (host + container)
    HEALTH_URL          = 'http://localhost:8085/actuator/health'
    HEALTH_MAX_WAIT_SEC = '120'
    HEALTH_INTERVAL_SEC = '5'
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
    
        // Preserve previous staging image for rollback (if it exists)
        bat """
          for /f "tokens=*" %%i in ('docker images -q %APP_NAME%:%STAGING_IMAGE_TAG%') do (
            docker image tag %APP_NAME%:%STAGING_IMAGE_TAG% %APP_NAME%:%PREV_IMAGE_TAG%
          )
    
          docker build -t %APP_NAME%:%VERSION% -f Dockerfile .
          docker image tag %APP_NAME%:%VERSION% %APP_NAME%:%STAGING_IMAGE_TAG%
        """
    
        // --- Pre-free 8085 in case an old/parallel stack is holding it ---
        powershell('''
          $port = [int]$env:STAGING_PORT
          $ids  = (docker ps --filter "publish=$port" -q) 2>$null
          if ($ids) {
            Write-Host "Port $port is in use; stopping containers: $ids"
            foreach ($id in $ids) {
              try { docker stop $id | Out-Null } catch {}
              try { docker rm   $id | Out-Null } catch {}
            }
          } else {
            Write-Host "Port $port is free."
          }
        ''')
    
        // Up/refresh the staging stack with a FIXED project name
        bat "docker compose -p %COMPOSE_PROJECT_NAME% -f %DOCKER_COMPOSE_FILE% up -d --remove-orphans"
    
        // Health gate against host-exposed 8085
        powershell('''
          $max = [int]$env:HEALTH_MAX_WAIT_SEC
          $interval = [int]$env:HEALTH_INTERVAL_SEC
          $url = $env:HEALTH_URL
          $ok = $false
          Write-Host "Waiting up to $max sec for health at $url ..."
          for ($t = 0; $t -lt $max; $t += $interval) {
            try {
              $resp = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 5
              if ($resp.StatusCode -ge 200 -and $resp.StatusCode -lt 300) {
                "Health OK (HTTP $($resp.StatusCode))" | Tee-Object -FilePath health-check.log -Append
                $ok = $true; break
              }
            } catch {
              Start-Sleep -Seconds $interval
              continue
            }
            Start-Sleep -Seconds $interval
          }
    
          if (-not $ok) {
            Write-Warning "Health check FAILED. Attempting rollback to previous image (if present)..."
            $prevImg = "$($env:APP_NAME):$($env:PREV_IMAGE_TAG)"
            $stagImg = "$($env:APP_NAME):$($env:STAGING_IMAGE_TAG)"
            $hasPrev = (docker images -q $prevImg)
            if ($hasPrev) {
              docker image tag $prevImg $stagImg
              docker compose -p $env:COMPOSE_PROJECT_NAME -f $env:DOCKER_COMPOSE_FILE up -d --remove-orphans
            } else {
              Write-Warning "No previous image found ($prevImg). Skipping rollback."
            }
            throw "Deploy failed health gate."
          }
        ''')
      }
      post {
        success {
          echo "Staging healthy at ${HEALTH_URL}. Image: ${APP_NAME}:${VERSION} (tag=${STAGING_IMAGE_TAG})."
          archiveArtifacts artifacts: "${DOCKER_COMPOSE_FILE}, health-check.log", fingerprint: true, allowEmptyArchive: false
        }
        failure {
          echo "Deploy failed; rollback attempted if previous image existed."
        }
        always {
          // Evidence collection (project-aware, no fixed names)
          powershell('''
            $proj = $env:COMPOSE_PROJECT_NAME
            $compose = $env:DOCKER_COMPOSE_FILE
    
            try { docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}" | Out-File -FilePath "docker-ps.txt" -Encoding utf8 } catch {}
            try { docker compose -p $proj -f $compose ps | Out-File -FilePath "compose-ps.txt" -Encoding utf8 } catch {}
    
            try {
              $ids = docker compose -p $proj -f $compose ps -q
              if ($ids) {
                foreach ($i in $ids) {
                  $name = (docker inspect --format "{{.Name}}" $i).TrimStart("/")
                  docker logs --since=15m $i | Out-File -FilePath ("deploy-logs-" + $name + ".txt") -Encoding utf8
                }
              }
            } catch {}
          ''')
          archiveArtifacts artifacts: 'docker-ps.txt, compose-ps.txt, deploy-logs-*.txt', allowEmptyArchive: true
        }
      }
    }


    stage('Release: Production (AWS CodeDeploy)') {
      when { branch 'main' }
      steps {
        withAWS(credentials: 'aws_prod', region: env.AWS_DEFAULT_REGION) {
    
          // Build the exact versioned image (local). Push to a registry if you use one.
          bat 'docker build -t spring-petclinic:%VERSION% .'
    
          // Write the vars the CodeDeploy hooks will read
          bat '''
            if not exist codedeploy mkdir codedeploy
            > release.env echo IMAGE_TAG=%VERSION%
            >> release.env echo SERVER_PORT=8086
          '''
    
          // Zip the revision (appspec + scripts + compose + env)
          bat 'powershell -NoProfile -Command "Compress-Archive -Path appspec.yml,scripts,release.env,docker-compose.prod.yml -DestinationPath codedeploy\\petclinic-%VERSION%.zip -Force"'
    
          // Upload to S3
          bat 'aws s3 cp codedeploy\\petclinic-%VERSION%.zip s3://%S3_BUCKET%/revisions/petclinic-%VERSION%.zip'
    
          // Trigger CodeDeploy and capture deploymentId
          bat '''
            for /f %%i in ('aws deploy create-deployment ^
              --application-name PetclinicApp ^
              --deployment-group-name Production ^
              --s3-location bucket=%S3_BUCKET%,key=revisions/petclinic-%VERSION%.zip,bundleType=zip ^
              --deployment-config-name CodeDeployDefault.AllAtOnce ^
              --auto-rollback-configuration enabled=true,events=DEPLOYMENT_FAILURE ^
              --query deploymentId --output text') do set DEPLOY_ID=%%i
            echo DeploymentId=%DEPLOY_ID%
          '''
    
          // Poll until Succeeded/Failed (max ~12 min)
          bat '''
            setlocal enabledelayedexpansion
            set STATUS=Created
            for /l %%t in (1,1,120) do (
              for /f %%s in ('aws deploy get-deployment --deployment-id %DEPLOY_ID% --query deploymentInfo.status --output text') do set STATUS=%%s
              echo Status: !STATUS!
              if /I "!STATUS!"=="Succeeded" goto :good
              if /I "!STATUS!"=="Failed"    goto :bad
              ping -n 6 127.0.0.1 >nul
            )
            :bad
            exit /b 1
            :good
          '''
        }
      }
      post {
        success { echo "Production released via CodeDeploy. Version=${VERSION} on port 8086."; }
        failure { echo "Release failed. Check CodeDeploy console and agent logs on the prod host."; }
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
