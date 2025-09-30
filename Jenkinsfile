pipeline {
  agent any
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
        sh 'chmod +x mvnw'
        sh './mvnw -B -V -DskipTests clean package'
      }
      post {
        success { archiveArtifacts artifacts: 'target/*.jar', fingerprint: true }
      }
    }

    // Tag the successful build on main
    stage('Tag Build') {
      when { branch 'main' }  // change to 'master' if your default branch is master
      steps {
        withCredentials([usernamePassword(credentialsId: 'github_push',
                                          usernameVariable: 'GIT_USER',
                                          passwordVariable: 'GIT_TOKEN')]) {
          sh """
            git config user.email "ci@jenkins"
            git config user.name  "Jenkins CI"
            git remote set-url origin https://${GIT_USER}:${GIT_TOKEN}@github.com/tthanh05/devops-petclinic.git
            git tag -a v${VERSION} -m "CI build ${VERSION}"
            git push origin v${VERSION}
          """
        }
      }
    }
  }
  post {
    success { echo "Build ${VERSION} archived and tagged." }
  }
}
