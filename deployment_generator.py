import sys
from kubernetes import config, client
from kubernetes.client.api.apps_v1_api import AppsV1Api

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
                    }
                },
                "spec": {
                    "containers": [
                        {
                            "env": [
                                {
                                    "name": "version",
                                    "value": app_version
                                }
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

    config.load_kube_config()
    k8s_v1_api = client.AppsV1Api()

    deployment_dict = generate_deployment_dict(
        app_name=app_name,
        namespace=namespace,
        docker_image=docker_image,
        app_version=app_version
    )

    if deployment_exists(k8s_v1_api, namespace, deployment_name=app_name):
        response =  k8s_v1_api.patch_namespaced_deployment(
            app_name,
            namespace,
            deployment_dict,
            pretty=True
        ) 
    else:
        response = k8s_v1_api.create_namespaced_deployment(
            namespace, deployment_dict, pretty=True
        )

    print(response)
    sys.exit(0)
