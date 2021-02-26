import vim
import os
import io
import ssl
import base64
import ftplib
import http.client
import hashlib
import filecmp
import shutil
from pathlib import Path
from Crypto import Random
from Crypto.Cipher import AES
# import codecs
ZOS_BACKUP_SUFFIX = ".zos.backup"
ZOS_TEMP_SUFFIX = ".zos.temp"
ZOS_DIFF_SUFFIX = ".zos.diff"
ZOS_CONN_FILE = ".zos.connection"

class AESCipher:
    def __init__(self):
        self.bs = 32
        secret = 'my little secret'
        if os.environ.get('MY_SECRET_KEY') is not None:
            secret = os.environ['MY_SECRET_KEY']
        self.key = hashlib.sha256(secret.encode()).digest()

    def encrypt(self, raw):
        raw = self._pad(raw).encode('utf-8')
        iv = Random.new().read(AES.block_size)
        cipher = AES.new(self.key, AES.MODE_CBC, iv)
        return base64.b64encode(iv + cipher.encrypt(raw))

    def decrypt(self, enc):
        enc = base64.b64decode(enc)
        iv = enc[:AES.block_size]
        cipher = AES.new(self.key, AES.MODE_CBC, iv)
        return self._unpad(cipher.decrypt(enc[AES.block_size:])).decode('utf-8')

    def _pad(self, s):
        return s + (self.bs - len(s) % self.bs) * chr(self.bs - len(s) % self.bs)

    @staticmethod
    def _unpad(s):
        return s[:-ord(s[len(s)-1:])]

class Connection:
    def __init__(self, path, host, port, user, password):
        self.root_path = path
        self.host = host
        self.port = port
        self.user = user
        self.password = password
        self.conn = http.client.HTTPSConnection(self.host, port=port, context=ssl._create_unverified_context())
        userAndPass = base64.b64encode(bytes(self.user + ':' + self.password, "utf-8")).decode("ascii")
        self.headers = {}
        self.headers['Authorization'] = 'Basic ' +  userAndPass
        self.headers['Content-Type'] = 'text/plain; charset=UTF-8'
        self.headers['X-IBM-Data-Type'] = 'text;fileEncoding=IBM-037'

    def list_folder(self, local_path):
        result = self.parse_local_path(local_path)
        local_sub_folder = result['local_sub_folder']
        remote_path = self._remote_path(local_sub_folder)
        # ftp
        print("remote_path", remote_path)
        ftp = ftplib.FTP(self.host)
        ftp.login(self.user, self.password)
        ftp.cwd(remote_path)
        data = []
        ftp.retrlines('LIST', data.append)
        ftp.quit()
        return data

    def sdsf_list(self):
        lines = []
        ftp = ftplib.FTP(self.host)
        ftp.login(self.user, self.password)
        ftp.sendcmd('SITE FILETYPE=JES')
        ftp.retrlines('LIST', lines.append)
        ftp.quit()

        sdsf_dir_path = os.path.join(self.root_path, "_spool")
        shutil.rmtree(sdsf_dir_path)
        if Path(sdsf_dir_path).exists() is not True:
            Path(sdsf_dir_path).mkdir(parents=True, exist_ok=True)

        i = 0
        for line in lines:
            job_name = line[0:8].strip()
            if job_name != 'JOBNAME':
                i = i + 1
                job_id = line[9:17].strip()
                job_text = 'x'
                if line[42:]:
                    job_text = line[42:].strip()
                if len(job_text) == 0:
                    job_text = 'x'
                job_dir_path = "%s/%s_%s_%s_%s" % (sdsf_dir_path, str(i).rjust(2,
                    '0'), job_name, job_text, job_id)
                Path(job_dir_path).mkdir(parents=True, exist_ok=True)
        return sdsf_dir_path

    def sdsf_get(self, job, step):
        parts = job.split('_')
        job_name = parts[1]
        if len(parts) < 3:
            return "Missing job id in this operation"
        job_id = parts[3]
        lines = []

        ftp = ftplib.FTP(self.host)
        ftp.login(self.user, self.password)
        ftp.sendcmd('SITE FILETYPE=JES')
        if step is not None:
            parts = step.split('_')
            step_id = parts[0]
            dest= "%s/_spool/%s/%s" % (self.root_path, job, step)
            src = job_id + '.' + step_id
            ftp.retrlines('RETR ' + src, lines.append)
            ftp.quit()
            with io.open(dest, 'w') as f:
                for line in lines:
                    f.write(line + "\n")
        else:
            ftp.retrlines('LIST ' + job_id, lines.append)
            ftp.quit()
            status = lines[1][27:33]
            if status == 'OUTPUT':
                for line in lines:
                    if line[0:8] == '        ':
                        step_id = line[9:12].strip()
                        if step_id != 'ID':
                            step_name = line[13:21].strip()
                            proc_step = line[22:30].strip()
                            dd_name = line[33:41].strip()
                            mem_name = "%s_%s_%s" % (step_id, dd_name,
                                      step_name)
                            dest= "%s/_spool/%s/%s.txt" % (self.root_path,
                                      job, mem_name)
                            src = "%s.%s" % (job_id, step_id)
                            Path(dest).touch()
            else:
                return "%s - %s is not in OUTPUT status" % (job_name, job_id)

        return ''

    def sdsf_del(self, member):
        parts = member.split('_')
        job_name = parts[1]
        job_id = parts[3]
        ftp = ftplib.FTP(self.host)
        ftp.login(self.user, self.password)
        ftp.sendcmd('SITE FILETYPE=JES')
        lines = ftp.delete(job_id)
        ftp.quit()
        job_dir_path = "%s/_spool/%s" % (self.root_path, member)
        shutil.rmtree(job_dir_path)
        return

    def submit_jcl(self, local_path):
        result = self.parse_local_path(local_path)
        local_member = result['local_member']
        ftp = ftplib.FTP(self.host)
        ftp.login(self.user, self.password)
        ftp.sendcmd('SITE FILETYPE=JES')
        with io.open(local_path, 'rb') as f:
            ftp.storlines('STOR ' + local_member, f)
        ftp.quit()

    def _remote_path(self, local_sub_folder, local_member=None):
        path = ''
        if self._is_pds(local_sub_folder):
            path = self._path_to_pds(local_sub_folder, local_member)
        else:
            if local_member is None:
                path = "/%s" % local_sub_folder
            else:
                remote_member = self._sanitize_remote_member(local_member)
                path = "/%s/%s" % (local_sub_folder, remote_member)
        return path

    @staticmethod
    def _sanitize_remote_member(local_member):
        remote_member = '' + local_member
        if remote_member.startswith('-read only-'):
            remote_member = remote_member.replace('-read only-','')
        if remote_member.startswith('-ascii-'):
            remote_member = remote_member.replace('-ascii-','')
        if remote_member.startswith('-1047-'):
            remote_member = remote_member.replace('-1047-','')
        return remote_member

    def _path_to_pds(self, local_sub_folder, local_member):
        parts = local_sub_folder.split(vim.eval('g:NERDTreePath.Slash()'))
        new_parts = []
        for p in parts:
            if (p[0] == '_'):
                p = '$' + p[1:]
            new_parts.append(p)
        dst = '/'.join(new_parts).replace('/', '.')
        path = ''
        if local_member is None:
            path = "'" + dst + "'"
        else:
            remote_member = self._sanitize_remote_member(local_member)
            if remote_member[0] == '_':
                remote_member = '$'+ remote_member[1:]
            remote_member = remote_member.split('.')[0].upper()
            path = "'%s(%s)'" % (dst, remote_member)
        return path

    @staticmethod
    def _encoding(local_member):
        encoding = 'IBM-037'
        if local_member.startswith('-ascii-'):
            encoding = 'ISO8859-1'
        if local_member.startswith('-1047-'):
            encoding = 'IBM-1047'
        return encoding

    @staticmethod
    def _is_pds(local_sub_folder):
        return local_sub_folder[0].upper() == local_sub_folder[0]

    def get_member(self, local_path):
        result = self.parse_local_path(local_path)
        local_sub_folder = result['local_sub_folder']
        local_member = result['local_member']
        encoding = self._encoding(local_member)
        remote_path = self._remote_path(local_sub_folder, local_member)
        local_dir_path = os.path.dirname(local_path)
        if Path(local_dir_path).exists() is not True:
            Path(local_dir_path).mkdir(parents=True, exist_ok=True)
        local_path  = os.path.join(local_dir_path, local_member)
        self._download_txt_file(remote_path, local_path, self._is_pds(local_sub_folder), encoding)
        backup_path = local_path + ZOS_BACKUP_SUFFIX
        diff_path = local_path + ZOS_DIFF_SUFFIX
        shutil.copyfile(local_path, backup_path)
        if Path(diff_path).exists():
            os.remove(diff_path)
        return local_path

    def _download_txt_file(self, remote_path, local_path, pds=True, encoding='IBM-037'):
        url_path = '/zosmf/restfiles/ds/' + remote_path.replace("'", '')
        if pds is not True:
            url_path = '/zosmf/restfiles/fs' + remote_path
            # for uss, always set to IBM-1047
            # if the file is already tagged, auto-conversion should happen
            # if the file is not tagged, then it's treated as IBM-1047 by
            # default
            self.headers['X-IBM-Data-Type'] = 'text;fileEncoding=IBM-1047'
        else:
            self.headers['X-IBM-Data-Type'] = 'text;fileEncoding=' + encoding
        print(url_path)
        self.headers['Content-Type'] = 'text/plain; charset=UTF-8'
        with io.open(local_path, 'w') as f:
            # data = f.read()
            self.conn.request("GET", url_path, headers=self.headers)
            response = self.conn.getresponse()
            print(response.status)
            print(response.reason)
            f.write(response.read().decode())
        self.conn.close()
        return


    def del_member(self, local_path):
        result = self.parse_local_path(local_path)
        local_sub_folder = result['local_sub_folder']
        local_member = result['local_member']
        remote_path = self._remote_path(local_sub_folder, local_member)
        backup_path = os.path.join(self.root_path, local_sub_folder, local_member + ZOS_BACKUP_SUFFIX)
        if Path(backup_path).exists():
            os.remove(backup_path)
        # ftp
        ftp = ftplib.FTP(self.host)
        ftp.login(self.user, self.password)
        ftp.delete(remote_path)
        ftp.quit()
        return remote_path

    def put_member(self, local_path, force=False):
        result = self.parse_local_path(local_path)
        local_sub_folder = result['local_sub_folder']
        local_member = result['local_member']
        if local_member.startswith('-read only-'):
            return 'read only, not uploaded'
        if (local_member.endswith(ZOS_DIFF_SUFFIX) or local_member.endswith(ZOS_TEMP_SUFFIX)):
            return 'temp file, not uploaded'
        encoding = self._encoding(local_member)
        remote_path = self._remote_path(local_sub_folder, local_member)
        backup_path = local_path + ZOS_BACKUP_SUFFIX
        temp_path = local_path + ZOS_TEMP_SUFFIX
        diff_path = local_path + ZOS_DIFF_SUFFIX

        url_path = '/zosmf/restfiles/ds/' + remote_path.replace("'", '')
        if self._is_pds(local_sub_folder) is not True:
            url_path = '/zosmf/restfiles/fs' + remote_path
            # for uss, always set to IBM-1047
            # if the file is already tagged, auto-conversion should happen
            # if the file is not tagged, then it's treated as IBM-1047 by
            # default
            self.headers['X-IBM-Data-Type'] = 'text;fileEncoding=IBM-1047'
        else:
            self.headers['X-IBM-Data-Type'] = 'text;fileEncoding=' + encoding

        # if Path(backup_path).exists() and force is False:
        if Path(backup_path).exists():
            if filecmp.cmp(local_path, backup_path) is True:
                return ''
            # get the file first to compare with the backup
            try:
                self._download_txt_file(remote_path, temp_path, self._is_pds(local_sub_folder), encoding)
            except Exception as e:
                if Path(temp_path).exists():
                    os.remove(temp_path)
                raise e
            if filecmp.cmp(temp_path, backup_path):
                command = "diff -e '%s' '%s' > '%s'" % (temp_path,
                        local_path, diff_path)
                os.system(command)
            else:
                if force is True:
                    command = "diff -e '%s' '%s' > '%s'" % (temp_path,
                            local_path, diff_path)
                    os.system(command)
                else:
                    command = "diff -DVERSION1 '%s' '%s' > '%s'" % (temp_path,
                            backup_path, diff_path)
                    # puts command
                    os.system(command)
                    if Path(temp_path).exists():
                        os.remove(temp_path)
                    return "file changed, check the diff file " + diff_path
            if Path(temp_path).exists():
                os.remove(temp_path)
            print('diff')
            self.headers['Content-Type'] = 'application/x-ibm-diff-e; charset=UTF-8'
            with io.open(diff_path, 'r') as f:
                data = f.read()
                self.conn.request("PUT", url_path, data, self.headers)
            response = self.conn.getresponse()
            print(response.status)
            print(response.reason)
            self.conn.close()
        else:
            self.headers['Content-Type'] = 'text/plain; charset=UTF-8'
            with io.open(local_path, 'r') as f:
                data = f.read()
                self.conn.request("PUT", url_path, data, self.headers)
            response = self.conn.getresponse()
            print(response.status)
            print(response.reason)
            self.conn.close()
        shutil.copyfile(local_path, backup_path)
        if Path(diff_path).exists():
            os.remove(diff_path)
        # print("return")
        return ''

    def parse_local_path(self, local_path):
        result = {}
        relative_path = os.path.relpath(local_path, self.root_path)
        parts = relative_path.split(vim.eval('g:NERDTreePath.Slash()'))
        if (Path(local_path).is_dir() is not True):
            result['local_member'] = parts.pop()
        result['local_sub_folder'] = '/'.join(parts)
        return result

    def refresh_files(self, force_delete=False, force_replace=False):
        for dir_path, dirs, files in os.walk(self.root_path):
            for file_name in files:
                local_path = os.path.join(dir_path, file_name)
                if file_name.endswith(ZOS_BACKUP_SUFFIX):
                    continue
                if file_name.endswith(ZOS_TEMP_SUFFIX):
                    continue
                if file_name.endswith(ZOS_DIFF_SUFFIX):
                    continue
                if file_name.startswith("."):
                    continue
                backup_path = local_path + ZOS_BACKUP_SUFFIX
                temp_path = local_path + ZOS_TEMP_SUFFIX
                diff_path = local_path + ZOS_DIFF_SUFFIX
                try:
                    result = self.parse_local_path(local_path)
                    local_sub_folder = result['local_sub_folder']
                    if local_sub_folder.startswith('_spool'):
                        continue
                    local_member = result['local_member']
                    encoding = self._encoding(local_member)
                    remote_path = self._remote_path(local_sub_folder, local_member)
                    self._download_txt_file(remote_path, temp_path, self._is_pds(local_sub_folder), encoding)
                except Exception as e:
                    print("Exception: ", str(e))
                    if Path(temp_path).exists():
                        os.remove(temp_path)
                    if (((str(e).find('nonexistent') != -1) or
                        (str(e).find('does not exist.') != -1)) and
                        force_delete):
                            os.remove(local_path)
                            if Path(diff_path).exists():
                                os.remove(diff_path)
                            print("Force deleted %s from local" % local_path)
                    continue

                if Path(backup_path).exists():
                    if filecmp.cmp(temp_path, backup_path):
                        os.remove(temp_path)
                        if Path(diff_path).exists():
                            os.remove(diff_path)
                    else:
                        if force_replace:
                            os.remove(local_path)
                            shutil.move(temp_path, local_path)
                            if Path(backup_path).exists():
                                os.remove(backup_path)
                            shutil.copyfile(local_path, backup_path)
                            if Path(diff_path).exists():
                                os.remove(diff_path)
                            print(local_path + ' replaced in local!')
                        else:
                            command = "diff -DVERSION1 '%s' '%s' > '%s'" % (temp_path, backup_path, diff_path)
                            os.system(command)
                            if Path(temp_path).exists():
                                os.remove(temp_path)
                            print("Difference found for %s, check the diff file" % local_path)
                else:
                    shutil.move(temp_path, backup_path)
                    if Path(diff_path).exists():
                        os.remove(diff_path)
        print("Done")
