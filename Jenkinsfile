pipeline {
  agent any

  tools { jdk 'jdk17' }   // Use the JDK tool you defined in Jenkins (matches your logs)

  options {
    timestamps()
    buildDiscarder(logRotator(numToKeepStr: '20'))
  }

  environment {
    // Reusable bits for Windows agent + Maven Wrapper
    MVN = 'mvnw.cmd -B -V --no-transfer-progress -Dmaven.repo.local=.m2\\repo'
    APP_NAME = 'spring-petclinic'
    GIT_SHA  = "${env.GIT_COMMIT?.take(7) ?: 'local'}"
    VERSION  = "${env.BUILD_NUMBER}-${GIT_SHA}"
  }

  stages {

    stage('Checkout') {
      steps {
        checkout scm
      }
    }

    stage('Build') {
      steps {
        // Prove correct Java toolchain in logs
        bat '"%JAVA_HOME%\\bin\\java" -version'

        // Keep formatting consistent (you used this in earlier runs)
        bat "${MVN} spring-javaformat:apply"

        // Fast packaging; tests run in dedicated stages below
        bat "${MVN} -DskipTests -Dcheckstyle.skip=true clean package"
      }
      post {
        success {
          // Archive the built JAR and fingerprint it (traceability)
          archiveArtifacts artifacts: 'target\\*.jar', fingerprint: true
        }
      }
    }

    stage('Test: Unit') {
      steps {
        // Run only unit tests (Surefire). Skip ITs explicitly.
        bat "${MVN} -Dcheckstyle.skip=true -DskipITs=true test"
      }
      post {
        // Parse Surefire XML reports (unit tests)
        always {
          junit testResults: 'target/surefire-reports/*.xml',
                keepLongStdio: true,
                allowEmptyResults: false
        }
      }
    }

    stage('Test: Integration') {
      steps {
        // Run only integration tests (Failsafe). Skip unit tests explicitly.
        bat "${MVN} -Dcheckstyle.skip=true -DskipITs=false failsafe:integration-test failsafe:verify"
      }
      post {
        // Parse Failsafe XML reports (integration tests)
        always {
          junit testResults: 'target/failsafe-reports/*.xml',
                keepLongStdio: true,
                allowEmptyResults: false
        }
      }
    }

    stage('Coverage Report') {
      steps {
        // Generate JaCoCo HTML report from jacoco.exec produced during tests
        bat "${MVN} -Dcheckstyle.skip=true jacoco:report"

        // Publish JaCoCo HTML to the build page
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
      when { branch 'main' }  // Only tag on main
      environment {
        // You should have a secret text credential named GIT_TOKEN in Jenkins
        GIT_HTTPS = "https://tthanh05:${GIT_TOKEN}@github.com/tthanh05/devops-petclinic.git"
      }
      steps {
        withCredentials([string(credentialsId: 'github_push_token', variable: 'GIT_TOKEN')]) {
          bat '''
            git config user.email "ci@jenkins"
            git config user.name  "Jenkins CI"
            git remote set-url origin %GIT_HTTPS%
            git tag -a v%BUILD_NUMBER%-%GIT_SHA% -m "CI build %BUILD_NUMBER% (%GIT_SHA%)"
            git push origin --tags
          '''
        }
      }
    }
  }

  post {
    success {
      echo "Build ${VERSION} archived, tests passed, coverage published, and tag pushed (if main)."
    }
    failure {
      echo "Build ${VERSION} failed. Check unit/IT report parsing (folders: surefire-reports / failsafe-reports)."
    }
  }
}
