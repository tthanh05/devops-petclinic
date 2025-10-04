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
    // DC_CACHE = '.dc'
    DC_CACHE = 'C:\\depcheck-cache'

    // ----- AWS (Release via CodeDeploy) -----
    AWS_REGION = 'ap-southeast-2'
    S3_BUCKET = 'petclinic-codedeploy-tthanh-ap-southeast-2'
    APP_NAME_AWS  = 'PetclinicApp'           // CodeDeploy application name
    DEPLOYMENT_GROUP  = 'Production'          // CodeDeploy deployment group name

    // ----- Staging (Compose) -----
    DOCKER_COMPOSE_FILE   = 'docker-compose.staging.yml'
    COMPOSE_PROJECT_NAME  = 'petclinic-ci'   // fixed name prevents duplicate stacks
    STAGING_IMAGE_TAG     = 'staging'
    PREV_IMAGE_TAG        = 'staging-prev'
    STAGING_PORT = '8100'
    HEALTH_URL   = 'http://localhost:8100/actuator/health'
    HEALTH_MAX_WAIT_SEC   = '120'
    HEALTH_INTERVAL_SEC   = '5'
  }

  stages {

    stage('Workspace clean') { 
      steps { deleteDir(); checkout scm } }

    // stage('Checkout') {
    //   steps { checkout scm }
    // }

    stage('Build') {
      steps {
        bat '"%JAVA_HOME%\\bin\\java" -version'
        bat "${MVN} spring-javaformat:apply"
        bat "${MVN} -DskipTests -Dcheckstyle.skip=true clean package"
        // stash name: 'petclinic-jar', includes: 'target/spring-petclinic-*.jar'
      }
      post {
        success { archiveArtifacts artifacts: 'target\\*.jar', fingerprint: true }
      }
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
      steps { bat "${MVN} -Dcheckstyle.skip=true -DskipITs=false -Djacoco.append=true failsafe:integration-test failsafe:verify" }
      post {
        always {
          junit testResults: 'target/failsafe-reports/*.xml', keepLongStdio: true, allowEmptyResults: false
        }
      }
    }

    // stage('Security: Dependency Scan (OWASP)') {
    //   steps {
    //     bat """
    //       ${MVN} -DskipTests=true ^
    //              org.owasp:dependency-check-maven:check ^
    //              -DdataDirectory=%DC_CACHE% ^
    //              -Dformat=ALL ^
    //              -DfailBuildOnCVSS=7 ^
    //              -Danalyzers.assembly.enabled=false ^
    //              -DautoUpdate=true
    //     """
    //   }
    //   post {
    //     always {
    //       archiveArtifacts artifacts: '''
    //         target/dependency-check-report.html,
    //         target/dependency-check-report.xml,
    //         target/dependency-check-report.json,
    //         target/dependency-check-junit.xml
    //       '''.trim().replaceAll("\\s+"," "), fingerprint: true, allowEmptyArchive: true
    //       publishHTML(target: [reportDir: 'target', reportFiles: 'dependency-check-report.html', reportName: 'OWASP Dependency-Check'])
    //       junit testResults: 'target/dependency-check-junit.xml', allowEmptyResults: true
    //     }
    //   }
    // }

    stage('Security: Dependency Scan (OWASP)') {
      steps {
        withCredentials([string(credentialsId: 'nvd_api_key', variable: 'NVD_API_KEY')]) {
          bat """
            if not exist "%DC_CACHE%" mkdir "%DC_CACHE%"
    
            ${MVN} -DskipTests=true ^
                   org.owasp:dependency-check-maven:check ^
                   -DdataDirectory=%DC_CACHE% ^
                   -Dformat=ALL ^
                   -DfailBuildOnCVSS=7 ^
                   -Danalyzers.assembly.enabled=false ^
                   -DautoUpdate=true ^
                   -Dnvd.api.key=%NVD_API_KEY%
          """
        }
      }
      post {
        always {
          archiveArtifacts artifacts: '''
            target/dependency-check-report.html,
            target/dependency-check-report.xml,
            target/dependency-check-report.json,
            target/dependency-check-junit.xml
          '''.trim().replaceAll("\\s+"," "), fingerprint: true, allowEmptyArchive: true
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

    // ==================== STAGING DEPLOY ====================
    stage('Deploy: Staging (Docker Compose on 8085 with Health Gate + Rollback)') {
      steps {
        bat 'docker --version'
        bat 'docker compose version'

        // keep previous tag for rollback + build new version
        bat """
          for /f "tokens=*" %%i in ('docker images -q %APP_NAME%:%STAGING_IMAGE_TAG%') do (
            docker image tag %APP_NAME%:%STAGING_IMAGE_TAG% %APP_NAME%:%PREV_IMAGE_TAG%
          )
          docker build -t %APP_NAME%:%VERSION% -f Dockerfile .
          docker image tag %APP_NAME%:%VERSION% %APP_NAME%:%STAGING_IMAGE_TAG%
        """

        // free port 8085 if anything (any stack) is publishing it
        powershell('''
          $port = [int]$env:STAGING_PORT
          $ids = (docker ps --filter "publish=$port" -q) 2>$null
          if ($ids) {
            Write-Warning "Port $port is in use; stopping containers: $ids"
            foreach ($id in $ids) {
              try { docker stop $id | Out-Null } catch {}
              try { docker rm   $id | Out-Null } catch {}
            }
          } else { Write-Host "Port $port appears free." }
        ''')

        // ensure THIS stack is down, then up (fixed project name)
        bat "docker compose -p %COMPOSE_PROJECT_NAME% -f %DOCKER_COMPOSE_FILE% down --remove-orphans"
        bat "docker compose -p %COMPOSE_PROJECT_NAME% -f %DOCKER_COMPOSE_FILE% up -d --remove-orphans"

        // health gate
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
            } catch { Start-Sleep -Seconds $interval; continue }
            Start-Sleep -Seconds $interval
          }
          if (-not $ok) {
            Write-Warning "Health check FAILED. Attempting rollback (if previous image exists)..."
            $prevImg = "$($env:APP_NAME):$($env:PREV_IMAGE_TAG)"
            $stagImg = "$($env:APP_NAME):$($env:STAGING_IMAGE_TAG)"
            $hasPrev = (docker images -q $prevImg)
            if ($hasPrev) {
              docker image tag $prevImg $stagImg
              docker compose -p $env:COMPOSE_PROJECT_NAME -f $env:DOCKER_COMPOSE_FILE up -d --remove-orphans
            } else {
              Write-Warning "No previous image found ($prevImg)."
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
    
    // ==================== PRODUCTION RELEASE (AWS CodeDeploy) ====================
    stage('Release: Production (AWS CodeDeploy)') {
      when { branch 'main' }
      steps {
        script {
          // Choose a release tag: use env.GIT_TAG if set, else the Jenkins build number
          env.RELEASE_TAG = (env.GIT_TAG?.trim()) ?: env.BUILD_NUMBER
        }
        
        withAWS(credentials: 'aws_prod', region: env.AWS_REGION) {
    
          // // Build the exact versioned image locally (optional for CodeDeploy itself)
          // bat 'docker build -t spring-petclinic:%VERSION% .'
    
          // // Package the revision CodeDeploy will pull
          // bat '''
          //   if not exist codedeploy mkdir codedeploy
          //   > release.env echo IMAGE_TAG=%VERSION%
          //   >> release.env echo SERVER_PORT=8086
          //   powershell -NoProfile -Command "Compress-Archive -Path appspec.yml,scripts,release.env,docker-compose.prod.yml -DestinationPath codedeploy\\petclinic-%VERSION%.zip -Force"
          // '''
    
          // // Upload to S3
          // bat 'aws s3 cp codedeploy\\petclinic-%VERSION%.zip s3://%S3_BUCKET%/revisions/petclinic-%VERSION%.zip --region %AWS_DEFAULT_REGION%'
    
          // // ---- Create deployment ----
          // powershell('''
          //   $depId = aws deploy create-deployment `
          //     --application-name PetclinicApp `
          //     --deployment-group-name Production `
          //     --s3-location bucket=$env:S3_BUCKET,key=revisions/petclinic-$env:VERSION.zip,bundleType=zip `
          //     --deployment-config-name CodeDeployDefault.AllAtOnce `
          //     --auto-rollback-configuration enabled=true,events=DEPLOYMENT_FAILURE `
          //     --region $env:AWS_DEFAULT_REGION `
          //     --query deploymentId --output text
          
          //   if (-not $depId -or $depId -eq 'None') {
          //     Write-Error 'Failed to create deployment (no deploymentId returned).'
          //   }
          //   Set-Content -Path dep_id.txt -Value $depId
          //   Write-Host "DeploymentId=$depId"
          // ''')
    
          // // ---- Poll deployment status ----
          // powershell('''
          //   $id = Get-Content dep_id.txt
          //   for ($i=0; $i -lt 120; $i++) {
          //     $st = aws deploy get-deployment `
          //       --deployment-id $id `
          //       --region $env:AWS_DEFAULT_REGION `
          //       --query deploymentInfo.status --output text
          //     Write-Host "Status: $st"
          //     if ($st -eq 'Succeeded') { exit 0 }
          //     if ($st -eq 'Failed')    { exit 1 }
          //     Start-Sleep -Seconds 6
          //   }
          //   Write-Error 'Timed out waiting for CodeDeploy deployment to finish.'
          // ''')
          bat """
            setlocal EnableDelayedExpansion
            set AWS_REGION=%AWS_REGION%
            set IMAGE_TAG=%RELEASE_TAG%
          
            rem ===== derive account & ECR host =====
            for /f %%A in ('aws sts get-caller-identity --query Account --output text') do set AWS_ACCOUNT=%%A
            set ECR_HOST=%AWS_ACCOUNT%.dkr.ecr.%AWS_REGION%.amazonaws.com
            set IMAGE_REPO=%ECR_HOST%/petclinic
          
            rem ===== ensure repo exists (no fragile caret) =====
            aws ecr describe-repositories --repository-name petclinic --region %AWS_REGION% >NUL 2>&1
            if errorlevel 1 (
              aws ecr create-repository --repository-name petclinic --region %AWS_REGION%
              if errorlevel 1 exit /b 1
            )
          
            rem ===== ECR docker login (no pipe) =====
            for /f "usebackq tokens=* delims=" %%P in (`aws ecr get-login-password --region %AWS_REGION%`) do set ECRPWD=%%P
            echo.!ECRPWD!> .ecrpwd.txt
            type .ecrpwd.txt | docker login --username AWS --password-stdin %ECR_HOST%
            del /q .ecrpwd.txt
            if errorlevel 1 exit /b 1
          
            rem ===== build / tag / push =====
            docker build -t spring-petclinic:%IMAGE_TAG% .
            if errorlevel 1 exit /b 1
          
            docker tag spring-petclinic:%IMAGE_TAG% %IMAGE_REPO%:%IMAGE_TAG%
            docker push %IMAGE_REPO%:%IMAGE_TAG%
            if errorlevel 1 exit /b 1
          
            rem ===== capture immutable digest =====
            for /F %%D in ('
              aws ecr describe-images --repository-name petclinic ^
                --image-ids imageTag=%IMAGE_TAG% ^
                --query "imageDetails[0].imageDigest" --output text --region %AWS_REGION%
            ') do set IMAGE_SHA=%%D
          
            rem ===== write release variables (read by EC2 scripts) =====
            >  release.env echo IMAGE_REPO=%IMAGE_REPO%
            >> release.env echo IMAGE_TAG=%IMAGE_TAG%
            >> release.env echo IMAGE_DIGEST=%IMAGE_REPO%@%IMAGE_SHA%
            >> release.env echo AWS_REGION=%AWS_REGION%
            >> release.env echo SERVER_PORT=8086
          
            rem ===== package and upload bundle for CodeDeploy =====
            if not exist codedeploy mkdir codedeploy
            powershell -NoProfile -Command "Compress-Archive -Path appspec.yml,scripts,docker-compose.prod.yml,release.env -DestinationPath codedeploy\\petclinic-%IMAGE_TAG%.zip -Force"
          
            aws s3 cp codedeploy\\petclinic-%IMAGE_TAG%.zip s3://%S3_BUCKET%/revisions/petclinic-%IMAGE_TAG%.zip --region %AWS_REGION%
            if errorlevel 1 exit /b 1
          
            rem ===== create CodeDeploy deployment =====
            aws deploy create-deployment ^
              --application-name "%APP_NAME_AWS%" ^
              --deployment-group-name "%DEPLOYMENT_GROUP%" ^
              --s3-location bucket=%S3_BUCKET%,bundleType=zip,key=revisions/petclinic-%IMAGE_TAG%.zip ^
              --region %AWS_REGION%
          """
        }
      }
      post {
        success { echo "Production released via CodeDeploy. Version=${VERSION} on port 8086." }
        failure { echo "Release failed. Check CodeDeploy console and the agent logs on the prod host." }
      }
    }

  }

  post {
    success { echo "Build ${VERSION} passed all gates and deployed to staging; release (if main) via CodeDeploy." }
    failure { echo "Build ${VERSION} failed. If failure is in Deploy/Release, check Docker/health or AWS setup." }
  }
}
