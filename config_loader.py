# config_loader.py 
import json
import os
 
def load_version_config():
    config_path = os.path.join(os.path.dirname(__file__),  './config/versions.json') 
    with open(config_path, 'r', encoding='utf-8') as f:
        data = json.load(f) 
    data['choices'] = [tuple(choice) for choice in data['choices']]
    return data
