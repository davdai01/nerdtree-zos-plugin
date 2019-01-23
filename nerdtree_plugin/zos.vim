if !has("python3")
    echo "vim has to be compiled with +python3 to run this"
    finish
endif

if exists('g:loaded_nerdtree_zos')
  finish
endif
let g:loaded_nerdtree_zos = 1

let s:plugin_root_dir = fnamemodify(resolve(expand('<sfile>:p')), ':h')

python3 << EOF
import sys
from os.path import normpath, join
import vim
import os
import yaml
import io
from pathlib import Path
plugin_root_dir = vim.eval('s:plugin_root_dir')
python_root_dir = normpath(join(plugin_root_dir, '..', 'python'))
sys.path.insert(0, python_root_dir)

from zos import Connection, AESCipher

def get_connection(path):
    file_name = join(path, ".zos.connection")
    with io.open(file_name, 'r') as stream:
        try:
            data = yaml.load(stream)
        except yaml.YAMLError as exc:
            print(exc)
            return
    host = data['host']
    user  = data['user']
    cipher = AESCipher()
    password = cipher.decrypt(data['password'])
    conn = Connection(path, host, user, password)
    return conn

def add_connection(path, host, user, password):
    if Path(path).exists():
       raise Exception('Connection folder already exists')
    Path(join(path, '_spool')).mkdir(parents=True, exist_ok=True)
    file_name = join(path, '.zos.connection')
    cipher = AESCipher()
    encrypted = cipher.encrypt(password)
    data = {}
    data['host'] = host
    data['user'] = user
    data['password'] = encrypted
    with io.open(file_name, 'w') as f:
        yaml.dump(data, f, default_flow_style=False)

EOF

call add(NERDTreeIgnore,'\.zos.connection$')
call add(NERDTreeIgnore,'\.zos.backup$')

call NERDTreeAddMenuSeparator()
call NERDTreeAddMenuItem({'text': '(z) Add a z/OS Connection', 'shortcut': 'z', 'callback': 'NERDTreeAddConnection'})
call NERDTreeAddMenuItem({'text': '(f) Add a PDS/folder', 'shortcut': 'f', 'isActiveCallback': 'NERDTreezOSEnabled2', 'callback': 'NERDTreeAddFolder'})
call NERDTreeAddMenuItem({'text': '(l) List members', 'shortcut': 'l', 'isActiveCallback': 'NERDTreezOSEnabled2',  'callback': 'NERDTreeListMembers'})
call NERDTreeAddMenuItem({'text': '(r) Refresh(re-download) the member', 'shortcut': 'r', 'isActiveCallback': 'NERDTreezOSMember',  'callback': 'NERDTreeGetMember'})
call NERDTreeAddMenuItem({'text': '(u) Force update the z/OS copy with the local copy', 'shortcut': 'u', 'isActiveCallback': 'NERDTreezOSMember',  'callback': 'NERDTreePutMember'})
call NERDTreeAddMenuItem({'text': '(s) Retrieve SDSF spool', 'shortcut': 's', 'isActiveCallback': 'NERDTreezOSEnabled',  'callback': 'NERDTreeSDSFList'})
call NERDTreeAddMenuItem({'text': '(i) Retrieve job output', 'shortcut': 'i', 'isActiveCallback': 'NERDTreeSDSFEnabled',  'callback': 'NERDTreeSDSFGet'})
call NERDTreeAddMenuItem({'text': '(p) Delete job output', 'shortcut': 'p', 'isActiveCallback': 'NERDTreeSDSFEnabled',  'callback': 'NERDTreeSDSFDel'})
call NERDTreeAddMenuItem({'text': '(p) Delete remotely and locally', 'shortcut': 'p', 'isActiveCallback': 'NERDTreezOSMember',  'callback': 'NERDTreeDelMember'})

function! NERDTreezOSEnabled2()
  let currentNode = g:NERDTreeFileNode.GetSelected()
  let zOSNode = s:InZOSFolder2(currentNode)
  if !empty(zOSNode)
    return 1
  endif
  return 0
endfunction

function! NERDTreezOSEnabled()
  let currentNode = g:NERDTreeFileNode.GetSelected()
  let zOSNode = s:InZOSFolder(currentNode)
  if !empty(zOSNode)
    return 1
  endif
  return 0
endfunction

function! NERDTreeSDSFEnabled()
  let currentNode = g:NERDTreeFileNode.GetSelected()
  let SDSFNode = s:InSDSFFolder(currentNode)
  if !empty(SDSFNode)
    return 1
  endif
  return 0
endfunction

function! NERDTreezOSMember()
  let currentNode = g:NERDTreeFileNode.GetSelected()
  let zOSNode = s:InZOSFolder2(currentNode)
  let result = 0
  if !empty(zOSNode)
python3 << EOF
curr_path = vim.eval('currentNode.path.str()')
if (Path(curr_path).is_dir() is not True):
    vim.command('let result = 1')
EOF
  endif
  return result
endfunction

function! s:promptToDelBuffer(bufnum, msg)
    echo a:msg
    if g:NERDTreeAutoDeleteBuffer || nr2char(getchar()) ==# 'y'
        " 1. ensure that all windows which display the just deleted filename
        " now display an empty buffer (so a layout is preserved).
        " Is not it better to close single tabs with this file only ?
        let s:originalTabNumber = tabpagenr()
        let s:originalWindowNumber = winnr()
        exec "tabdo windo if winbufnr(0) == " . a:bufnum . " | exec ':enew! ' | endif"
        exec "tabnext " . s:originalTabNumber
        exec s:originalWindowNumber . "wincmd w"
        " 3. We don't need a previous buffer anymore
        exec "bwipeout! " . a:bufnum
    endif
endfunction

com! JCLSubmit call SubJCL(expand("%:p"))
function! SubJCL(fname)
  call g:NERDTree.CursorToTreeWin()
  let node = b:NERDTreeRoot.findNode(g:NERDTreePath.New(a:fname))
  let zOSNode = s:InZOSFolder2(node)
  let rc = 0
  if !empty(zOSNode)
python3 << EOF
try:
    zos_path = vim.eval('zOSNode.path.str()')
    curr_path = vim.eval('node.path.str()')
    conn = get_connection(zos_path)
    relative_path = curr_path.replace(zos_path + vim.eval('g:NERDTreePath.Slash()'),'')
    parts = relative_path.split(vim.eval('g:NERDTreePath.Slash()'))
    member = parts.pop()
    folder = '/'.join(parts)
    conn.submit_jcl(folder,member)
except Exception as e:
    vim.command('let rc = 1')
    raise e
EOF
    if rc == 0
      call s:echo('Job submitted')
    endif
  endif
endfunction

function! NERDTreeAddConnection()
  let name = input('Input the connection name: ')
  let host = input('Input the host address: ')
  let user = input('Input the user id: ')
  let password = input('Input the password: ')
  let rc = 0
python3 << EOF
try:
    add_connection('./' + vim.eval('name'), vim.eval('host'), vim.eval('user'), vim.eval('password'))
except Exception as e:
    vim.command('let rc = 1')
    raise e
EOF
  if rc == 0
    call b:NERDTree.render()
    call s:echo('Connection added')
  endif
endfunction

function! NERDTreeSDSFList()
  let currentNode = g:NERDTreeFileNode.GetSelected()
  let zOSNode = s:InZOSFolder(currentNode)
  if !empty(zOSNode)
    let rc = 0
python3 << EOF
try:
    zos_path = vim.eval('zOSNode.path.str()')
    curr_path = vim.eval('currentNode.path.str()')
    conn = get_connection(zos_path)
    new_path = conn.sdsf_list()
    vim.command("let newNodeName = '%s'" % new_path)
except Exception as e:
    vim.command('let rc = 1')
    raise e
EOF
    if rc == 0
      call zOSNode.refresh()
      let newTreeNode = b:NERDTreeRoot.findNode(g:NERDTreePath.New(newNodeName))
      call newTreeNode.open()
      call newTreeNode.putCursorHere(1, 0)
      call b:NERDTree.render()
      call s:echo('SDSF list refreshed')
    endif
  endif
endfunction

function! NERDTreeSDSFGet()
  let currentNode = g:NERDTreeFileNode.GetSelected()
  let zOSNode = s:InZOSFolder(currentNode)
  if !empty(zOSNode)
    python3 << EOF
zos_path = vim.eval('zOSNode.path.str()')
curr_path = vim.eval('currentNode.path.str()')
conn = get_connection(zos_path)
relative_path = curr_path.replace(zos_path + vim.eval('g:NERDTreePath.Slash()'),'')
parts = relative_path.split(vim.eval('g:NERDTreePath.Slash()'))
step = None
if (Path(curr_path).is_dir() is not True):
    step = parts.pop()
job = parts.pop()
msg = conn.sdsf_get(job, step)
if (msg == ''):
    if (Path(curr_path).is_dir() is not True):
        vim.command("call currentNode.open({'where': 'p'})")
        vim.command("call s:echo('Output retreived')")
    else:
        vim.command('call currentNode.refresh()')
        vim.command('call currentNode.open()')
        vim.command('call b:NERDTree.render()')
        vim.command("call s:echo('Job output list retreived')")
else:
    vim.command("call s:echoWarning('" + msg + "')")
EOF
  endif
endfunction

function! NERDTreeSDSFDel()
  let currentNode = g:NERDTreeFileNode.GetSelected()
  let zOSNode = s:InZOSFolder(currentNode)
  if !empty(zOSNode)
    let rc = 0
python3 << EOF
try:
    zos_path = vim.eval('zOSNode.path.str()')
    curr_path = vim.eval('currentNode.path.str()')
    conn = get_connection(zos_path)
    relative_path = curr_path.replace(zos_path + vim.eval('g:NERDTreePath.Slash()'),'')
    parts = relative_path.split(vim.eval('g:NERDTreePath.Slash()'))
    if (Path(curr_path).is_dir() is not True):
        parts.pop()
    job = parts.pop()
    conn.sdsf_del(job)
    vim.command("let newNodeName = '" + conn.path + "/_spool'")
except Exception as e:
    vim.command('let rc = 1')
    raise e
EOF
    if rc == 0
      call zOSNode.refresh()
      let newTreeNode = b:NERDTreeRoot.findNode(g:NERDTreePath.New(newNodeName))
      call newTreeNode.putCursorHere(1, 0)
      call NERDTreeRender()
      call s:echo('Job deleted')
    endif
  endif
endfunction

function! NERDTreeAddFolder()
  let name = input('Input the PDS/folder name: ')
  let currentNode = g:NERDTreeFileNode.GetSelected()
  let zOSNode = s:InZOSFolder2(currentNode)
  if !empty(zOSNode)
    let rc = 0
python3 << EOF
try:
    name = vim.eval('name')
    zos_folder = vim.eval('zOSNode.path.str()')
    member = name
    if (name.find('/') == -1):
        new_name = name.replace('.', '/').upper()
        parts = new_name.split('/')
        new_parts = []
        for part in parts:
            if (part[0] == '$'):
                part[0] = '_'
            new_parts.append(part)
        member = '/'.join(parts)

    dest = join(zos_folder, member)
    Path(dest).mkdir(parents=True, exist_OK=True)
except Exception as e:
    vim.command('let rc = 1')
    raise e
EOF
    if rc == 0
      call zOSNode.refresh()
      call b:NERDTree.render()
      call s:echo('Folder added')
    endif
  endif
endfunction

function! NERDTreeGetMember()
  let currentNode = g:NERDTreeFileNode.GetSelected()
  let zOSNode = s:InZOSFolder2(currentNode)
  if !empty(zOSNode)
    let rc = 0
python3 << EOF
try:
    zos_path = vim.eval('zOSNode.path.str()')
    curr_path = vim.eval('currentNode.path.str()')
    conn = get_connection(zos_path)
    relative_path = curr_path.replace(zos_path + vim.eval('g:NERDTreePath.Slash()'),'')
    parts = relative_path.split(vim.eval('g:NERDTreePath.Slash()'))
    member = parts.pop()
    folder = '/'.join(parts)
    conn.get_member(folder, member)
except Exception as e:
    vim.command('let rc = 1')
    raise e
EOF
    if rc == 0
      call zOSNode.refresh()")
      call b:NERDTree.render()")
      call currentNode.open({'where': 'p'})")
      redraw
      call s:echo('Member refreshed')
    endif
  endif
endfunction

function! NERDTreePutMember()
  let currentNode = g:NERDTreeFileNode.GetSelected()
  let zOSNode = s:InZOSFolder2(currentNode)
  if !empty(zOSNode)
    " echo 'found'
    " echo zOSNode.path.str()
    let rc = 0
python3 << EOF
try:
    zos_path = vim.eval('zOSNode.path.str()')
    curr_path = vim.eval('currentNode.path.str()')
    conn = get_connection(zos_path)
    relative_path = curr_path.replace(zos_path + vim.eval('g:NERDTreePath.Slash()'),'')
    parts = relative_path.split(vim.eval('g:NERDTreePath.Slash()'))
    member = parts.pop()
    folder = '/'.join(parts)
    conn.put_member(folder,member, True)
except Exception as e:
    vim.command('let rc = 1')
    raise e
EOF
    if rc == 0
      call zOSNode.refresh()
      call b:NERDTree.render()
      call currentNode.open({'where': 'p'})
      redraw
      call s:echo('Member uploaded')
    endif
  endif
endfunction

function! NERDTreeDelMember()
  let currentNode = g:NERDTreeFileNode.GetSelected()
  let confirmed = 0
  echo "Delete the current node\n" .
     \ "======================================\n".
     \ "Are you sure you wish to delete the node: \n".
     \ "" . currentNode.path.str() . " (yN):"
  let choice = nr2char(getchar())
  let confirmed = choice ==# 'y'
  if confirmed
    let zOSNode = s:InZOSFolder2(currentNode)
    if !empty(zOSNode)
      " echo 'found'
      " echo zOSNode.path.str()
      let rc = 0
python3 << EOF
try:
    zos_path = vim.eval('zOSNode.path.str()')
    curr_path = vim.eval('currentNode.path.str()')
    conn = get_connection(zos_path)
    relative_path = curr_path.replace(zos_path + vim.eval('g:NERDTreePath.Slash()'),'')
    parts = relative_path.split(vim.eval('g:NERDTreePath.Slash()'))
    member = parts.pop()
    folder = '/'.join(parts)
    conn.del_member(folder,member)
except Exception as e:
    vim.command('let rc = 1')
    raise e
EOF
      if rc == 0
        call currentNode.delete()
        call NERDTreeRender()
        "if the node is open in a buffer, ask the user if they want to
        "close that buffer
        let bufnum = bufnr("^".currentNode.path.str()."$")
        if buflisted(bufnum)
          let prompt = "\nNode deleted.\n\nThe file is open in buffer ". bufnum . (bufwinnr(bufnum) ==# -1 ? " (hidden)" : "") .". Delete this buffer? (yN)"
          call s:promptToDelBuffer(bufnum, prompt)
        endif

        redraw
        call s:echo('Member deleted')
      endif
    endif
  else
    call s:echo("delete aborted")
  endif
endfunction

function! NERDTreeListMembers()
  let currentNode = g:NERDTreeFileNode.GetSelected()
  " echo 'current node'
  " echo currentNode.path.str()
  let zOSNode = s:InZOSFolder2(currentNode)
  if !empty(zOSNode)
    " echo 'found'
    " echo zOSNode.path.str()
python3 << EOF
zos_path = vim.eval('zOSNode.path.str()')
curr_path = vim.eval('currentNode.path.str()')
conn = get_connection(zos_path)
relative_path = curr_path.replace(zos_path + vim.eval('g:NERDTreePath.Slash()'),'')
parts = relative_path.split(vim.eval('g:NERDTreePath.Slash()'))
if (Path(curr_path).is_dir() is not True):
    parts.pop()
folder = '/'.join(parts)
lines = conn.list_folder(folder)
index = 0
page_count = 20
message = ''
new_path = ''
# found = false
status = 'not found'
result = ''
not_finished = True
# while lines.count - index > page_count
while not_finished:
    size = 0
    if len(lines) - index > page_count:
        size = page_count
    else:
        size = len(lines) - index
        not_finished = False
    part = lines[index:index+page_count]
    i = 0
    part = []
    for p in lines[index:index+page_count]:
        part.append(str(i).ljust(5) + p)
        i = i + 1
        index = index + 1
    if not_finished:
        prompt = "\n".join(part) + "\nPlease input the member name: (or press ENTER to page through the member list)\n"
    else:
        prompt = "\n".join(part) + "\nEnd of list\nPlease input the member name:"

    vim.command("let result = input('" + prompt + "')")
    result = vim.eval('result')
    # puts "result: #{result}"
    if result != '':
        if result[0] == "=":
            idx = result[1:]
            # puts "idx: #{idx}"
            if idx.upper() == 'X':
                # found = True
                status = "canceled"
                break
            idx = int(float(idx))
            if folder[0].upper() == folder[0]:
                # pds
                if part[0][5:11] == 'Volume':
                    result = part[idx][61:].strip()
                else:
                    result = part[idx][5:13].strip()
            else:
                # unix
                result = part[idx][59:].strip()
        if folder[0].upper() == folder[0]:
            # pds
            if part[0][5:11] == 'Volume':
                status = 'folder found'
            else:
                status = 'member found'
        else:
            # unix
            if part[idx][5] == 'd':
                status = "folder found"
            else:
                status = "member found"

        break
if status == "member found":
    not_finished = True
    while not_finished:
        prompt = "special attributes [0-none]/1-read only/2-ascii/3-1047: "
        vim.command("let prefix = input('%s')" % prompt)
        prefix = vim.eval('prefix')
        if (prefix == ''):
            break
        elif (prefix == '1'):
            result = "-read only-" + result
            break
        elif (prefix == '2'):
            result = "-asscii-" + result
            break
        elif (prefix == '3'):
            result = "-1047-" + result
            break

    prompt = "file suffix: "
    vim.command("let suffix = input('%s')" % prompt)
    suffix = vim.eval('suffix')
    if suffix != '':
        result = result + '.' + suffix

    new_path = conn.get_member(folder,result)
    vim.command("let newNodeName = '%s'" % new_path)
    vim.command("call zOSNode.refresh()")
    if Path(curr_path).is_dir():
        vim.command('call currentNode.open()')
    vim.command("call b:NERDTree.render()")
    vim.command("let newTreeNode = b:NERDTreeRoot.findNode(g:NERDTreePath.New(newNodeName))")
    vim.command("call newTreeNode.putCursorHere(1, 0)")
    vim.command("call s:echo('Member downloaded')")
elif status == "canceled":
    vim.command("call s:echo('Operation canceled')")
elif status == "folder found":
    if result.find('/') == -1:
        result.replace('.','/')
    dest = join(curr_path, result)
    Path(dest).mkdir(parents=True, exist_ok=True)
    vim.command("let newNodeName = '%s'" % dest)
    vim.command("call zOSNode.refresh()")
    if Path(curr_path).is_dir():
        vim.command('call currentNode.open()')
    vim.command("call b:NERDTree.render()")
    vim.command("call s:echo('Folder added')")
EOF
  endif
endfunction

function! NERDTreeZOSRefreshListener(event)
  let path = a:event.subject
  let action = a:event.action
  let params = a:event.params

python3 << EOF
path_name = vim.eval('path.str()')
found = False
path = Path(path_name)
if path.is_dir():
    # puts Pathname(path_name).basename
    if path.name == '_spool':
        # puts 'found _spool'
        vim.command('call path.flagSet.clearFlags("sdsf")')
        vim.command('call path.flagSet.addFlag("sdsf", "-SDSF-")')
    else:
        for c in path.iterdir():
            if c.name == '.zos.connection':
                vim.command('call path.flagSet.clearFlags("zos")')
                vim.command('call path.flagSet.addFlag("zos", "-zOS-")')
                found = True
if found is False:
    vim.command('call path.flagSet.clearFlags("zos")')
EOF
endfunction

augroup nerdtreezosplugin
  autocmd BufWritePost * call s:ZOSFileUpdate(expand("%:p"))
augroup END

function! s:ZOSFileUpdate(fname)
  if !g:NERDTree.IsOpen()
    return
  endif
  call g:NERDTree.CursorToTreeWin()
  " try
    let currentNode = b:NERDTreeRoot.findNode(g:NERDTreePath.New(a:fname))
    let zOSNode = s:InZOSFolder2(currentNode)
    if !empty(zOSNode)
      " echo 'found'
      " echo zOSNode.path.str()
python3 << EOF
try:
    zos_path = vim.eval('zOSNode.path.str()')
    curr_path = vim.eval('currentNode.path.str()')
    conn = get_connection(zos_path)
    relative_path = curr_path.replace(zos_path + vim.eval('g:NERDTreePath.Slash()'),'')
    parts = relative_path.split(vim.eval('g:NERDTreePath.Slash()'))
    member = parts.pop()
    folder = '/'.join(parts)
    msg = conn.put_member(folder,member)
    # puts "msg: #{msg}."
    print("msg ", msg)
except Exception as e:
    raise e
else:
    if msg == '':
        vim.command("call s:echo('Member uploaded')")
    else:
        vim.command("call s:echoWarning('" + msg + "')")
        vim.command("call zOSNode.refresh()")
        vim.command("call b:NERDTree.render()")
EOF
    endif
  " catch
  " endtry

endfunction

function! s:InZOSFolder(node)
  try
    " let node = b:NERDTreeRoot.findNode(path))
    let node = a:node
    " echo node.displayString()
    " echo node.path.str()
    while !empty(node)
      " echo node.displayString()
      " echo node.path.str()
      if node.displayString() =~ '\[-zOS-\]'
        return node
      endif
      let node = node.parent
    endwhile
  catch
    return {}
  endtry
  return {}
endfunction

" In ZOS folder but not in SDSF folder, could use a better name
function! s:InZOSFolder2(node)
  try
    " let node = b:NERDTreeRoot.findNode(path))
    let node = a:node
    " echo node.displayString()
    " echo node.path.str()
    while !empty(node)
      " echo node.displayString()
      " echo node.path.str()
      if node.displayString() =~ '\[-SDSF-\]'
        return {}
      endif
      if node.displayString() =~ '\[-zOS-\]'
        return node
      endif
      let node = node.parent
    endwhile
  catch
    return {}
  endtry
  return {}
endfunction

function! s:InSDSFFolder(node)
  try
    " let node = b:NERDTreeRoot.findNode(path))
    let node = a:node
    " echo node.displayString()
    " echo node.path.str()
    while !empty(node)
      " echo node.displayString()
      " echo node.path.str()
      if node.displayString() =~ '\[-SDSF-\]'
        return node
      endif
      let node = node.parent
    endwhile
  catch
    return {}
  endtry
  return {}
endfunction

function! s:echo(msg)
  redraw
  echomsg "NERDTree: " . a:msg
endfunction

function! s:echoWarning(msg)
  echohl warningmsg
  call s:echo(a:msg)
  echohl normal
endfunction

autocmd FileType nerdtree call s:AddHighlighting()
function! s:AddHighlighting()
  syn match NERDTreezOS #\[-zOS-\]#
  hi def link NERDTreezOS statement
  syn match NERDTreeSDSF #\[-SDSF-\]#
  hi def link NERDTreeSDSF statement
endfunction

call g:NERDTreePathNotifier.AddListener("init", "NERDTreeZOSRefreshListener")
call g:NERDTreePathNotifier.AddListener("refresh", "NERDTreeZOSRefreshListener")
call g:NERDTreePathNotifier.AddListener("refreshFlags", "NERDTreeZOSRefreshListener")
