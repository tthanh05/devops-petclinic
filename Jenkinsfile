pipeline {
  agent any
  tools { jdk 'jdk17' }   // <— use the JDK you just configured
  options { timestamps(); buildDiscarder(logRotator(numToKeepStr: '20')) }
  environment {
    APP_NAME = 'spring-petclinic'
    GIT_SHA  = "${env.GIT_COMMIT?.take(7) ?: 'local'}"
    VERSION  = "${env.BUILD_NUMBER}-${GIT_SHA}"
  }
  stages {
    stage('Checkout') { steps { checkout scm } }

    stage('Build') {
      steps {
        // Show Java version to be sure it's 17
        bat '"%JAVA_HOME%\\bin\\java" -version'
        bat 'mvnw.cmd -B -V -DskipTests clean package'
      }
      post {
        success { archiveArtifacts artifacts: 'target\\*.jar', fingerprint: true }
      }
    }

    stage('Tag Build') {
      when { branch 'main' }
      steps {
        withCredentials([usernamePassword(credentialsId: 'github_push',
          usernameVariable: 'GIT_USER', passwordVariable: 'GIT_TOKEN')]) {
          bat """
            git config user.email "ci@jenkins"
            git config user.name  "Jenkins CI"
            git remote set-url origin https://%GIT_USER%:%GIT_TOKEN%@github.com/tthanh05/devops-petclinic.git
            git tag -a v%VERSION% -m "CI build %VERSION%"
            git push origin v%VERSION%
          """
        }
      }
    }
  }
  post { success { echo "Build %VERSION% archived and tagged." } }
}
