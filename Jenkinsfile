pipeline {
  agent any
  options { timestamps() }   // removed ansiColor
  stages {
    stage('Checkout') { steps { checkout scm } }
    stage('Build') {
      steps {
        bat 'mvnw.cmd -B -V -DskipTests clean package'
      }
      post {
        success { archiveArtifacts artifacts: 'target\\*.jar', fingerprint: true }
      }
    }
  }
}
