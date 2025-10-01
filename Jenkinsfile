pipeline {
  agent any
  options {
    timestamps()
    skipDefaultCheckout(true)
    buildDiscarder(logRotator(numToKeepStr: '30'))
  }
  environment {
    MVN = 'mvnw.cmd -B -V --no-transfer-progress -Dmaven.repo.local=.m2\\repo'
    MAVEN_OPTS = '-Xms256m -Xmx1024m'
  }
  stages {
    stage('Declarative: Checkout SCM') {
      steps {
        checkout scm
        echo "GIT_COMMIT=${env.GIT_COMMIT}"
        echo "BRANCH_NAME=${env.BRANCH_NAME}"
      }
    }

    stage('Build') {
      steps {
        bat "${env.MVN} spring-javaformat:apply"
        bat "${env.MVN} -DskipTests -Dcheckstyle.skip=true clean package"
      }
      post {
        success {
          archiveArtifacts artifacts: 'target/**/*.jar,target/classes/META-INF/sbom/*.json', fingerprint: true
        }
      }
    }

    stage('Test: Unit') {
      steps {
        bat "${env.MVN} -Dcheckstyle.skip=true -DskipITs=true test"
      }
      post {
        always {
          junit testResults: 'target/surefire-reports/*.xml',
                allowEmptyResults: false,
                skipPublishingChecks: true
        }
      }
    }

    stage('Test: Integration') {
      steps {
        bat "${env.MVN} -Dcheckstyle.skip=true -DskipITs=false failsafe:integration-test failsafe:verify"
      }
      post {
        always {
          junit testResults: 'target/failsafe-reports/*.xml',
                allowEmptyResults: false,
                skipPublishingChecks: true
        }
      }
    }

    stage('Coverage Report') {
      steps {
        bat "${env.MVN} -Dcheckstyle.skip=true jacoco:report"
      }
      post {
        success {
          publishHTML(target: [
            reportDir: 'target/site/jacoco',
            reportFiles: 'index.html',
            reportName: 'JaCoCo Coverage',
            keepAll: true,
            allowMissing: false,
            alwaysLinkToLastBuild: true
          ])
        }
      }
    }

    stage('Code Quality (SonarQube)') {
      when {
        expression { fileExists('sonar-project.properties') }
      }
      steps {
        withSonarQubeEnv('SonarLocal-9000') {
          bat "${env.MVN} -DskipTests -Dcheckstyle.skip=true sonar:sonar"
        }
      }
    }

    stage('Tag Build') {
      when {
        allOf { branch 'main'; expression { currentBuild.currentResult == 'SUCCESS' } }
      }
      steps {
        withCredentials([usernamePassword(credentialsId: 'github_push', usernameVariable: 'GIT_USER', passwordVariable: 'GIT_TOKEN')]) {
          bat """
            git config user.email "ci@jenkins"
            git config user.name  "Jenkins CI"
            git remote set-url origin https://%GIT_USER%:%GIT_TOKEN%@github.com/tthanh05/devops-petclinic.git
            git tag -a v${env.BUILD_NUMBER}-${env.GIT_COMMIT.substring(0,7)} -m "CI build ${env.BUILD_NUMBER} (${env.GIT_COMMIT.substring(0,7)})"
            git push origin --tags
          """
        }
      }
    }
  }
  post {
    success { echo "Build ${env.BUILD_NUMBER}-${env.GIT_COMMIT.substring(0,7)} archived, tests passed, coverage published, Sonar (if configured) executed, and tag pushed (if main)." }
    failure { echo "Build ${env.BUILD_NUMBER}-${env.GIT_COMMIT.substring(0,7)} failed. Check surefire/failsafe report paths and credentials." }
  }
}
