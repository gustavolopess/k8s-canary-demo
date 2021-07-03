import sys
import os
import time
from kubernetes import client, config
from kubernetes.client.api.custom_objects_api import CustomObjectsApi
import requests

PHASE_SUCCEEDED = 'Succeeded'
PHASE_FAILED = 'Failed'
PHASE_INITIALIZING = 'Initializing'
PHASE_PROMOTING = 'Promoting'
PHASE_PROGRESSING = 'Progressing'
PHASE_NOT_FOUND = 'Not Found'


def get_canary_phase(custom_resources_k8s_api: CustomObjectsApi):
    ret = custom_resources_k8s_api.get_namespaced_custom_object(
        version='v1beta1', 
        name='nestjs-canary-demo', 
        group='flagger.app', 
        namespace='nestjs-canary-demo', 
        plural='canaries'
    )
    return ret.get('status', dict()).get('phase', PHASE_NOT_FOUND)


if __name__ == '__main__':
    config.load_kube_config()
    custom_objects_api = client.CustomObjectsApi()
    
    application_url = sys.argv[-1]

    phase = get_canary_phase(custom_objects_api)
    has_progressed = False    

    while not has_progressed or phase in [PHASE_PROGRESSING, PHASE_INITIALIZING, PHASE_PROMOTING]:
        print(f'\nCurrent phase: {phase}')
        print(
            requests.get(application_url, headers={'Host': 'nestjs-canary.demo.com'}).content.decode()
        )
        
        has_progressed = phase == PHASE_PROGRESSING 
        phase = get_canary_phase(custom_objects_api)
        
        time.sleep(1)
        

    if phase in [PHASE_FAILED, PHASE_NOT_FOUND]:
        print(f'Canary failed: phase={phase}')
        sys.exit(1)
    
    print(f'Canary succeeded: phase={phase}')
    sys.exit(0)
