import sys
import os
from kubernetes import client
from kubernetes.client.api.apps_v1_api import AppsV1Api
from kubernetes.client.api.core_v1_api import CoreV1Api
from datetime import datetime
from requests.packages.urllib3.exceptions import InsecureRequestWarning
import warnings
import uuid

warnings.simplefilter('ignore', InsecureRequestWarning)

def generate_deployment_dict(
    app_name: str,
    namespace: str,
    docker_image: str, 
    app_version: str
):
    return {
        "apiVersion": "apps/v1",
        "kind": "Deployment",
        "metadata": {
            "labels": {
                "app": app_name
            },
            "annotations": {
                "timestamp": str(datetime.now())
            },
            "name": app_name,
            "namespace": namespace,
        },
        "spec": {
            "selector": {
                "matchLabels": {
                    "app": app_name
                }
            },
            "template": {
                "metadata": {
                    "labels": {
                        "app": app_name
                    },
                    "annotation": {
                        "sidecar.istio.io/rewriteAppHTTPProber": "false",
                        "timestamp": str(datetime.now())
                    }
                },
                "spec": {
                    "containers": [
                        {
                            "env": [
                                {
                                    "name": "version",
                                    "value": app_version
                                },
                                {
                                    "name": "deployment_id",
                                    "value": str(uuid.uuid4())
                                },
                            ],
                            "image": f'{docker_image}:{app_version}',
                            "imagePullPolicy": "IfNotPresent",
                            "livenessProbe": {
                                "httpGet": {
                                    "path": "/health",
                                    "port": 3001,
                                },
                            },
                            "name": app_name,
                            "ports": [
                                {
                                    "containerPort": 3001,
                                    "protocol": "TCP"
                                }
                            ],
                            "readinessProbe": {
                                "httpGet": {
                                    "path": "/health",
                                    "port": 3001,
                                },
                            },
                            "resources": {
                                "limits": {
                                    "cpu": "100m",
                                    "memory": "256Mi"
                                },
                                "requests": {
                                    "cpu": "50m",
                                    "memory": "128Mi"
                                }
                            },
                        }
                    ],
                }
            }
        },
    }

def deployment_exists(k8s_api: AppsV1Api, namespace: str, deployment_name: str) -> bool:
    deployments = k8s_api.list_namespaced_deployment(namespace)
    for deployment in deployments.items:
        if deployment.metadata.name == deployment_name:
            return True
    return False

if __name__ == '__main__':
    [app_name, namespace, docker_image, app_version] = sys.argv[1:]

    token = os.getenv('SERVICEACCOUNT_TOKEN')
    cluster_host = os.getenv('CLUSTER_HOST')
    service_account = os.getenv('NAMESPACE_SERVICEACCOUNT')
    username = f'system:serviceaccount:nestjs-canary-demo:github-actions-deployer' 

    configuration = client.Configuration(
        username=username, 
        host=cluster_host, 
        api_key={"authorization": "Bearer " + token},
    )
    configuration.verify_ssl = False

    a_api_client = client.ApiClient(configuration)
    
    k8s_v1_api = client.AppsV1Api(a_api_client)

    deployment_dict = generate_deployment_dict(
        app_name=app_name,
        namespace=namespace,
        docker_image=docker_image,
        app_version=app_version
    )


    if deployment_exists(k8s_v1_api, namespace, deployment_name=app_name):
        k8s_v1_api.replace_namespaced_deployment(app_name, namespace, deployment_dict)
    else:
        response = k8s_v1_api.create_namespaced_deployment(
            namespace, deployment_dict, pretty=True
        )

    sys.exit(0)
