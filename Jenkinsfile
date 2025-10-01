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
    // Cache for OWASP Dependency-Check (faster repeated runs)
    DC_CACHE = '.dc'
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
        // append=true lets JaCoCo merge IT coverage with unit coverage later
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

    /* -------------------- SECURITY (SCA) --------------------
     * OWASP Dependency-Check scans all dependencies for known CVEs.
     * - Fails the build on CVSS >= 7 (you can tune this).
     * - Uses a suppression file for documented false positives.
     * - Publishes HTML + JUnit reports and archives raw outputs.
     * ------------------------------------------------------ */
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
          // Keep everything for audit
          archiveArtifacts artifacts: '''
            target/dependency-check-report.html,
            target/dependency-check-report.xml,
            target/dependency-check-report.json,
            target/dependency-check-junit.xml
          '''.trim().replaceAll("\\s+", " "), fingerprint: true, allowEmptyArchive: true

          // Nice HTML report on the build page
          publishHTML(target: [
            reportDir: 'target',
            reportFiles: 'dependency-check-report.html',
            reportName: 'OWASP Dependency-Check',
            keepAll: true,
            allowMissing: false,
            alwaysLinkToLastBuild: false
          ])
          // Archive everything for evidence
          archiveArtifacts artifacts: 'target/dependency-check-report/**, target/dependency-check-json*', allowEmptyArchive: true
          // Also surface as a test-like report so it’s visible in Jenkins UI
          junit testResults: 'target/dependency-check-junit.xml', allowEmptyResults: true
        }
        failure {
          echo '❌ High severity CVEs detected (CVSS >= 7). See "OWASP Dependency-Check" report and mitigation notes.'
        }
        unsuccessful {
          echo '⚠️ Review Dependency-Check results. Use the suppression file ONLY for genuine false-positives with justification.'
        }
      }
    }

    /* -------------------- CODE QUALITY (SonarQube) -------------------- */
    stage('Code Quality: SonarQube') {
      steps {
        // Make sure the XML exists for coverage
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

            // Diagnostics to tie CE task to this build
            bat 'cd'
            bat 'dir /a .scannerwork'
            bat 'type .scannerwork\\report-task.txt'
            bat 'for /d /r %%i in (.scannerwork) do @echo FOUND: %%i'
          }
        }
        archiveArtifacts artifacts: '.scannerwork/**', fingerprint: false, allowEmptyArchive: true
      }
    }

    stage('Quality Gate') {
      steps {
        timeout(time: 10, unit: 'MINUTES') {
          // Webhook should be set to http://host.docker.internal:8092/sonarqube-webhook/ (your Jenkins port)
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
  }

  post {
    success {
      echo "Build ${VERSION} archived, tests passed, coverage published, security scan clean (or justified), and tag pushed (if main)."
    }
    failure {
      echo "Build ${VERSION} failed. If failure happened in Tag Build, check credential type/binding."
    }
  }
}
