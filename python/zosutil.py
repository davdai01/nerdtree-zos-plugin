import yaml
import io
import os
from pathlib import Path
import zos

def get_connection(path):
    file_path = os.path.join(path, zos.ZOS_CONN_FILE)
    with io.open(file_path, 'r') as stream:
        data = yaml.load(stream, Loader=yaml.FullLoader)
    host = data['host']
    user  = data['user']
    port  = data['port']
    cipher = zos.AESCipher()
    password = cipher.decrypt(data['password'])
    conn = zos.Connection(path, host, port, user, password)
    return conn

def update_connection(path, host, port, user, password):
    file_path = os.path.join(path,  zos.ZOS_CONN_FILE)
    with io.open(file_path, 'r') as stream:
        data = yaml.load(stream, Loader=yaml.FullLoader)
    if host != '':
        data['host'] = host
    if port != '':
        data['port'] = port
    if user != '':
        data['user'] = user
    if password != '':
        cipher = zos.AESCipher()
        encrypted = cipher.encrypt(password)
        data['password'] = encrypted
    with io.open(file_path, 'w') as f:
        yaml.dump(data, f, default_flow_style=False)

def add_connection(path, host, port, user, password):
    if Path(path).exists():
       raise Exception('Connection folder already exists')
    Path(os.path.join(path, '_spool')).mkdir(parents=True, exist_ok=True)
    Path(os.path.join(path, user.upper())).mkdir(parents=True, exist_ok=True)
    file_path = os.path.join(path,  zos.ZOS_CONN_FILE)
    cipher = zos.AESCipher()
    encrypted = cipher.encrypt(password)
    data = {}
    data['host'] = host
    data['port'] = port
    data['user'] = user
    data['password'] = encrypted
    with io.open(file_path, 'w') as f:
        yaml.dump(data, f, default_flow_style=False)

def zos_update_password(password):
    cipher = zos.AESCipher()
    encrypted = cipher.encrypt(password)
    cwd = os.getcwd()
    for child in os.listdir(cwd):
        dir_path = os.path.join(cwd, child)
        if os.path.isdir(dir_path):
            file_path = os.path.join(dir_path, zos.ZOS_CONN_FILE)
            if Path(file_path).exists():
                with io.open(file_path, 'r') as stream:
                    data = yaml.load(stream, Loader=yaml.FullLoader)
                data['password'] = encrypted
                with io.open(file_path, 'w') as f:
                    yaml.dump(data, f, default_flow_style=False)

def zos_clean():
    cwd = os.getcwd()
    for dir_path, dirs, files in os.walk(cwd):
        for file_name in files:
            path = os.path.join(dir_path, file_name)
            if os.path.basename(path).endswith(zos.ZOS_BACKUP_SUFFIX):
                if Path(path.replace(zos.ZOS_BACKUP_SUFFIX, "")).exists() is not True:
                    os.remove(path)
                    print("Deleted ", path)
            if os.path.basename(path).endswith(zos.ZOS_TEMP_SUFFIX):
                if Path(path.replace(zos.ZOS_TEMP_SUFFIX, "")).exists() is not True:
                    os.remove(path)
                    print("Deleted ", path)
    print("Done")
