pipeline {
  agent any
  options { timestamps(); ansiColor('xterm') }
  stages {
    stage('Checkout') { steps { checkout scm } }
    stage('Build') {
      steps {
        sh 'chmod +x mvnw'
        sh './mvnw -B -V -DskipTests clean package'
      }
      post { success { archiveArtifacts artifacts: 'target/*.jar', fingerprint: true } }
    }
  }
}
