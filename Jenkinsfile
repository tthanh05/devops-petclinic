pipeline {
  agent any
  tools { jdk 'jdk17' }
  options { timestamps(); buildDiscarder(logRotator(numToKeepStr: '20')) }

  environment {
    APP_NAME   = 'spring-petclinic'
    GIT_SHA    = "${env.GIT_COMMIT?.take(7) ?: 'local'}"
    VERSION    = "${env.BUILD_NUMBER}-${GIT_SHA}"
    MAVEN_REPO = ".m2\\repo"   // local cache to speed up builds on Windows agent
  }

  stages {
    stage('Checkout') {
      steps { checkout scm }
    }

    stage('Build') {
      steps {
        bat '"%JAVA_HOME%\\bin\\java" -version'
        bat 'mvnw.cmd -B -V -DskipTests -Dmaven.repo.local=%MAVEN_REPO% --no-transfer-progress clean package'
      }
      post {
        success {
          archiveArtifacts artifacts: 'target\\*.jar', fingerprint: true
        }
      }
    }

    // ---------- Test: Unit (Surefire runs **/*Test.java) ----------
    stage('Test: Unit') {
      steps {
        bat 'mvnw.cmd -B -Dmaven.repo.local=%MAVEN_REPO% -DskipITs=true --no-transfer-progress test'
      }
      post {
        always {
          junit 'target\\surefire-reports\\*.xml'   // fail the build if tests failed
        }
      }
    }

    // ---------- Test: Integration (Failsafe runs **/*IT.java) ----------
    stage('Test: Integration') {
      steps {
        // Boots a real Spring context (your *IT.java tests use @SpringBootTest).
        bat 'mvnw.cmd -B -Dmaven.repo.local=%MAVEN_REPO% -DskipTests=true -DskipITs=false --no-transfer-progress failsafe:integration-test failsafe:verify'
      }
      post {
        always {
          junit 'target\\failsafe-reports\\*.xml'   // fail the build if any IT failed
        }
      }
    }

    // ---------- Coverage HTML (JaCoCo) ----------
    stage('Coverage Report') {
      steps {
        // JaCoCo report also runs during 'verify', but this ensures HTML is present.
        bat 'mvnw.cmd -B -Dmaven.repo.local=%MAVEN_REPO% --no-transfer-progress jacoco:report'
      }
      post {
        always {
          publishHTML(target: [
            reportDir : 'target\\site\\jacoco',
            reportFiles: 'index.html',
            reportName : 'JaCoCo Coverage'
          ])
        }
      }
    }

    // ---------- Tag only successful main builds ----------
    stage('Tag Build') {
      when { branch 'main' }
      steps {
        withCredentials([usernamePassword(credentialsId: 'github_push',
                                          usernameVariable: 'GIT_USER',
                                          passwordVariable: 'GIT_TOKEN')]) {
          bat """
            git config user.email "ci@jenkins"
            git config user.name  "Jenkins CI"
            git remote set-url origin https://%GIT_USER%:%GIT_TOKEN%@github.com/tthanh05/devops-petclinic.git
            git tag -a v%BUILD_NUMBER%-%GIT_COMMIT:~0,7% -m "CI build %BUILD_NUMBER% (%GIT_COMMIT:~0,7%)"
            git push origin --tags
          """
        }
      }
    }
  }

  post {
    success { echo "Build ${VERSION} archived, tests passed, coverage published, and tag pushed (if main)." }
  }
}
