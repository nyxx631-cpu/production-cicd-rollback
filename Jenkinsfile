pipeline {
    agent any

    options {
        timestamps()
        disableConcurrentBuilds()
        timeout(time: 20, unit: 'MINUTES')
    }

    environment {
        // Set your Docker Hub repository
        DOCKERHUB_REPO = 'nikhil031020/production-cicd-rollback'
        IMAGE_TAG      = "${BUILD_NUMBER}"
        NAMESPACE      = 'production-demo'
        DEPLOYMENT     = 'rollback-demo'
        CONTAINER      = 'web'
        SERVICE        = 'rollback-demo-service'
        KUBECONFIG     = 'C:\\ProgramData\\Jenkins\\.jenkins\\.kube\\config'
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Test') {
            steps {
                powershell '''
                    $ErrorActionPreference = "Stop"

                    if (-not (Test-Path "app\\index.html")) { throw "app\\index.html missing" }
                    if ((Get-Item "app\\index.html").Length -eq 0) { throw "app\\index.html is empty" }
                    
                    Select-String -Path "app\\index.html" -Pattern "Production-Style CI/CD Pipeline" -Quiet | Out-Null
                    if (-not $?) { throw "Pattern check failed in app\\index.html" }

                    if (-not (Test-Path "Dockerfile")) { throw "Dockerfile missing" }
                    if (-not (Test-Path "k8s\\deployment.yaml")) { throw "k8s\\deployment.yaml missing" }
                    if (-not (Test-Path "scripts\\health-check.sh")) { throw "scripts\\health-check.sh missing" }

                    Write-Host "Basic application checks passed."
                '''
            }
        }

        stage('Build Docker Image') {
            steps {
                bat """
                    docker build -t %DOCKERHUB_REPO%:%IMAGE_TAG% .
                """
            }
        }

        stage('Security Scan') {
            steps {
                bat """
                    trivy image --severity HIGH,CRITICAL --exit-code 1 --format json --output trivy-report.json %DOCKERHUB_REPO%:%IMAGE_TAG%
                """
            }
            post {
                always {
                    archiveArtifacts(
                        artifacts: 'trivy-report.json',
                        allowEmptyArchive: true
                    )
                }
            }
        }

        stage('Push Docker Image') {
            steps {
                withCredentials([
                    usernamePassword(
                        credentialsId: 'dockerhub-credentials',
                        usernameVariable: 'DH_USER',
                        passwordVariable: 'DH_TOKEN'
                    )
                ]) {
                    bat '''
                        echo %DH_TOKEN% | docker login -u %DH_USER% --password-stdin
                        docker push %DOCKERHUB_REPO%:%IMAGE_TAG%
                        docker logout
                    '''
                }
            }
        }

        stage('Deploy and Verify') {
            steps {
                script {
                    try {
                        powershell '''
                            $ErrorActionPreference = "Stop"

                            # Apply namespace and service
                            kubectl --kubeconfig="$env:KUBECONFIG" apply -f k8s/namespace.yaml
                            kubectl --kubeconfig="$env:KUBECONFIG" apply -f k8s/service.yaml

                            # Save previous image for diagnostics
                            $prevImage = kubectl --kubeconfig="$env:KUBECONFIG" get deployment $env:DEPLOYMENT -n $env:NAMESPACE -o jsonpath='{.spec.template.spec.containers[?(@.name=="web")].image}'
                            $prevImage | Out-File -FilePath previous-image.txt -Encoding utf8
                            Write-Host "Previous image: $prevImage"

                            # Deploy new image
                            kubectl --kubeconfig="$env:KUBECONFIG" set image deployment/$env:DEPLOYMENT "$($env:CONTAINER)=$($env:DOCKERHUB_REPO):$($env:IMAGE_TAG)" -n $env:NAMESPACE

                            # Wait for rollout
                            kubectl --kubeconfig="$env:KUBECONFIG" rollout status deployment/$env:DEPLOYMENT -n $env:NAMESPACE --timeout=180s

                            # Start port-forward in background job
                            $pfJob = Start-Job -ScriptBlock {
                                param($kc, $ns, $svc)
                                kubectl --kubeconfig="$kc" port-forward -n "$ns" "service/$svc" 18080:80
                            } -ArgumentList $env:KUBECONFIG, $env:NAMESPACE, $env:SERVICE

                            try {
                                # Give port-forward 5 seconds to bind
                                Start-Sleep -Seconds 5

                                # Execute health-check (curl/Invoke-RestMethod)
                                $response = Invoke-RestMethod -Uri "http://127.0.0.1:18080/" -TimeoutSec 10
                                Write-Host "Health check response received successfully."
                            }
                            finally {
                                Stop-Job -Job $pfJob
                                Remove-Job -Job $pfJob
                            }
                        '''
                    } catch (err) {
                        echo 'Deployment or health verification failed.'
                        echo 'Attempting Kubernetes rollback.'

                        try {
                            powershell '''
                                $ErrorActionPreference = "Stop"

                                kubectl --kubeconfig="$env:KUBECONFIG" rollout undo deployment/$env:DEPLOYMENT -n $env:NAMESPACE
                                kubectl --kubeconfig="$env:KUBECONFIG" rollout status deployment/$env:DEPLOYMENT -n $env:NAMESPACE --timeout=180s

                                Write-Host "Rollback rollout completed."
                            '''
                        } catch (rollbackErr) {
                            echo 'CRITICAL: Rollback could not be verified.'
                            powershell '''
                                kubectl --kubeconfig="$env:KUBECONFIG" get pods -n $env:NAMESPACE
                                kubectl --kubeconfig="$env:KUBECONFIG" get events -n $env:NAMESPACE --sort-by=.lastTimestamp
                            '''
                            error('Deployment failed and rollback verification failed.')
                        }

                        error('Deployment failed; rollback was attempted and verified.')
                    }
                }
            }
        }
    }

    post {
        success {
            echo "Release ${IMAGE_TAG} deployed and health-checked successfully."
        }
        failure {
            echo 'Pipeline failed. Review Console Output and Kubernetes events.'
        }
        always {
            echo 'Pipeline execution finished.'
        }
    }
}
