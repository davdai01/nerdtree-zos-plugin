from os.path import join
import vim
import os
import io
import base64
import ftplib
import hashlib
import filecmp
import shutil
from pathlib import Path
from Crypto import Random
from Crypto.Cipher import AES

def is_pds(folder):
    print("is_pds", folder)
    return folder[0].upper() == folder[0]

class AESCipher:
    def __init__(self):
        self.bs = 32
        secret = 'my little secret'
        if os.environ['MY_SECRET_KEY'] is not None:
            secret = os.environ['MY_SECRET_KEY']
        self.key = hashlib.sha256(secret.encode()).digest()

    def encrypt(self, raw):
        raw = self._pad(raw)
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
    def __init__(self, path, host, user, password):
        self.path = path
        self.host = host
        self.user = user
        self.password = password

    def list_folder(self, folder):
        path = "/" + folder
        print("folder", folder)
        if is_pds(folder):
            parts = folder.split(vim.eval('g:NERDTreePath.Slash()'))
            new_parts = []
            for p in parts:
                if (p[0] == '_'):
                    p[0] = '$'
                new_parts.append(p)
            path = '/'.join(new_parts)
            path = "'" + path.replace('/', '.') + "'"
        # ftp
        print("path", path)
        ftp = ftplib.FTP(self.host)
        ftp.login(self.user, self.password)
        ftp.cwd(path)
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

        sdsf_folder = join(self.path, "_spool")
        shutil.rmtree(sdsf_folder)
        if Path(sdsf_folder).exists() is not True:
            Path(sdsf_folder).mkdir(parents=True, exist_ok=True)

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
                job_folder = "%s/%s_%s_%s_%s" % (sdsf_folder, str(i).rjust(2,
                    '0'), job_name, job_text, job_id)
                Path(job_folder).mkdir(parents=True, exist_ok=True)
        return sdsf_folder

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
            dest= "%s/_spool/%s/%s" % (self.path, job, step)
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
                            dest= "%s/_spool/%s/%s.txt" % (self.path,
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
        job_folder = "%s/_spool/%s" % (self.path, member)
        shutil.rmtree(job_folder)
        return

    def submit_jcl(self, relative_path, member):

        src = join(self.path, relative_path, member)
        ftp = ftplib.FTP(self.host)
        ftp.login(self.user, self.password)
        ftp.sendcmd('SITE FILETYPE=JES')
        with io.open(src, 'rb') as f:
            ftp.storlines('STOR ' + member, f)
        ftp.quit()

    def get_member(self, relative_path, member):
        dest_member = '' + member
        if dest_member[0] == '$':
            dest_member[0] = '_'
        encoding = 'IBM-037'
        if member.startswith('-read only-'):
            member = member.replace('-read only-','')
        if member.startswith('-ascii-'):
            member = member.replace('-ascii-','')
            encoding = 'ISO8859-1'
        if member.startswith('-1047-'):
            member = member.replace('-1047-','')
            encoding = 'IBM-1047'
        if member[0] == '_':
           member[0] = '$'
        source_member = '' + member
        src = ''
        if is_pds(relative_path):
            source_member = member.split('.')[0].upper()
            parts = relative_path.split(vim.eval('g:NERDTreePath.Slash()'))
            new_parts = []
            for part in parts:
                if part[0] == '_':
                    part[0] = '$'
                new_parts.append(part)
            folder = '/'.join(new_parts)
            src = "'%s(%s)'" % (folder.replace('/','.'), source_member)
        else:
            src = "/#{relative_path}/#{source_member}"
            src = "/%s/%s" % (relative_path, source_member)
        dest_folder = join(self.path, relative_path)
        if Path(dest_folder).exists() is not True:
            Path(dest_folder).mkdir(parents=True, exist_ok=True)
        dest  = join(dest_folder, dest_member)
        self._download_txt_file(src, dest, encoding)
        backup = "%s.zos.backup" % dest
        diff = "%s.zos.diff" % dest
        shutil.copyfile(dest, backup)
        if Path(diff).exists():
            os.remove(diff)
        return dest

    def _download_txt_file(self, src, dest, encoding='IBM-037'):
        # ftp
        ftp = ftplib.FTP(self.host)
        ftp.login(self.user, self.password)
        cmd = "SITE SBD=(%s,ISO8859-1)" % encoding
        # puts cmd
        ftp.sendcmd(cmd)
        lines = []
        ftp.retrlines('RETR ' + src, lines.append)
        ftp.quit()
        with io.open(dest, 'w') as f:
            for line in lines:
                f.write(line + "\n")
        return


    def del_member(self, relative_path, member):
        dest_member = '' + member
        if member.startswith('-read only-'):
            member = member.replace('-read only-','')
        if member.startswith('-ascii-'):
            member = member.replace('-ascii-','')
        if member.startswith('-1047-'):
            member = member.replace('-1047-','')
        if member[0] == '_':
            member[0] = '$'
        source_member = '' + member
        src = ''
        if is_pds(relative_path):
            source_member = member.split('.')[0].upper()
            parts = relative_path.split(vim.eval('g:NERDTreePath.Slash()'))
            new_parts = []
            for part in parts:
                if part[0] == '_':
                    part[0] = '$'
                new_parts.append(part)
            folder = '/'.join(new_parts)
            src = "'%s(%s)'" % (folder.replace('/','.'), source_member)
        else:
            src = "%s/%s" % (relative_path, source_member)
        backup_file = join(self.path, relative_path, member + ".zos.backup")
        if Path(backup_file).exists():
            os.remove(backup_file)
        # ftp
        ftp = ftplib.FTP(self.host)
        ftp.login(self.user, self.password)
        ftp.delete(src)
        ftp.quit()
        return src

    def put_member(self, relative_path, member, force=False):
        if member.startswith('-read only-'):
            return 'read only, not uploaded'
        if (member.endswith('.zos.diff') or member.endswith('.zos.temp')):
            return 'temp file, not uploaded'
        src_folder = join(self.path, relative_path)
        dest = ''
        encoding = 'IBM-037'
        dest_member = '' + member
        if member.startswith('-ascii-'):
            dest_member = member.replace('-ascii-','')
            encoding = 'ISO8859-1'
        if member.startswith('-1047-'):
            dest_member = member.replace('-1047-','')
            encoding = 'IBM-1047'
        if dest_member[0] == '_':
            dest_member[0] = '$'
        if is_pds(relative_path):
            parts = relative_path.split(vim.eval('g:NERDTreePath.Slash()'))
            new_parts = []
            for part in parts:
                if part[0] == '_':
                    part[0] = '$'
                new_parts.append(part)
            folder = '/'.join(new_parts)
            dest = "'%s(%s)'" % (folder.replace('/','.'), dest_member.split('.')[0])
        else:
            dest = "/%s/%s" % (relative_path, dest_member)
        src = join(src_folder, member)
        backup_file = src + ".zos.backup"
        temp_file = src + ".zos.temp"
        diff_file = src + ".zos.diff"
        if Path(backup_file).exists() and force is False:
            # get the file first to compare with the backup
            try:
                self._download_txt_file(dest, temp_file, encoding)
            except Exception as e:
                if Path(temp_file).exists():
                    os.remove(temp_file)
                raise e
            if filecmp.cmp(temp_file, backup_file):
                if Path(temp_file).exists():
                    os.remove(temp_file)
            else:
                command = "diff -DVERSION1 '%s' '%s' > '%s'" % (temp_file,
                        backup_file, diff_file)
                # puts command
                os.system(command)
                if Path(temp_file).exists():
                    os.remove(temp_file)
                return "file changed, check the diff file " + diff_file
        print("uploading ", src)
        print("to ", dest)
        ftp = ftplib.FTP(self.host)
        ftp.login(self.user, self.password)
        cmd = "SITE SBD=(%s,ISO8859-1)" % encoding
        ftp.sendcmd(cmd)
        with io.open(src, 'rb') as f:
            ftp.storlines('STOR ' + dest, f)
        ftp.quit()
        print("uploading done", src)
        print("downloading backup_file")
        self._download_txt_file(dest, backup_file, encoding)
        print("downloading backup_file done")
        if Path(diff_file).exists():
            os.remove(diff_file)
        print("return")
        return ''
