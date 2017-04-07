" rubyfile ./zos_explorer.rb
if exists('g:loaded_nerdtree_zos')
  finish
endif
let g:loaded_nerdtree_zos = 1

call add(NERDTreeIgnore,'\.zos.connection$')
" call add(NERDTreeIgnore,'\.zos.cksum$')
call add(NERDTreeIgnore,'\.zos.backup$')
" call add(NERDTreeIgnore,'\.zos.temp$')

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
    ruby << EOF
    curr_path = VIM::evaluate('currentNode.path.str()')
    if !Pathname(curr_path).directory?
      VIM::command('let result = 1')
    end
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
  " try
    let node = b:NERDTreeRoot.findNode(g:NERDTreePath.New(a:fname))
    let zOSNode = s:InZOSFolder2(node)
    if !empty(zOSNode)
      ruby << EOF
      zos_path = VIM::evaluate('zOSNode.path.str()')
      curr_path = VIM::evaluate('node.path.str()')
      conn = VIM::ZOS::Connection.new
      conn.load_from_path(zos_path)
      relative_path = curr_path.gsub("#{zos_path}#{VIM::evaluate('g:NERDTreePath.Slash()')}",'')
      parts = relative_path.split(VIM::evaluate('g:NERDTreePath.Slash()'))
      member = parts.pop
      folder = parts.join('/')
      conn.submit_jcl(folder,member)
EOF
    call s:echo('Job submitted')
    endif
  " catch
  "   echo 'submit error'
  " endtry
endfunction

function! NERDTreeAddConnection()
  let name = input('Input the connection name: ')
  let host = input('Input the host address: ')
  let user = input('Input the user id: ')
  let password = input('Input the password: ')
  ruby << EOF
  VIM::ZOS::Connection.add_connection("./#{VIM::evaluate("name")}",VIM::evaluate("host"),VIM::evaluate("user"),VIM::evaluate("password"))
EOF
  call zOSNode.refresh()
  call b:NERDTree.render()
  call s:echo('Connection added')
  " redraw
endfunction

function! NERDTreeSDSFList()
  let currentNode = g:NERDTreeFileNode.GetSelected()
  let zOSNode = s:InZOSFolder(currentNode)
  if !empty(zOSNode)
    ruby << EOF
    zos_path = VIM::evaluate('zOSNode.path.str()')
    curr_path = VIM::evaluate('currentNode.path.str()')
    conn = VIM::ZOS::Connection.new
    conn.load_from_path(zos_path)
    new_path = conn.sdsf_list()
    VIM::command("let newNodeName = '#{new_path}'")
EOF
    call zOSNode.refresh()
    let newTreeNode = b:NERDTreeRoot.findNode(g:NERDTreePath.New(newNodeName))
    call newTreeNode.open()
    call newTreeNode.putCursorHere(1, 0)
    call b:NERDTree.render()
    call s:echo('SDSF list refreshed')
    " redraw
" EOF
"     call zOSNode.refresh()
"     call b:NERDTree.render()
"     redraw
  endif
endfunction

function! NERDTreeSDSFGet()
  let currentNode = g:NERDTreeFileNode.GetSelected()
  let zOSNode = s:InZOSFolder(currentNode)
  if !empty(zOSNode)
    " echo 'found'
    " echo zOSNode.path.str()
    ruby << EOF
    zos_path = VIM::evaluate('zOSNode.path.str()')
    curr_path = VIM::evaluate('currentNode.path.str()')
    conn = VIM::ZOS::Connection.new
    conn.load_from_path(zos_path)
    relative_path = curr_path.gsub("#{zos_path}#{VIM::evaluate('g:NERDTreePath.Slash()')}",'')
    parts = relative_path.split(VIM::evaluate('g:NERDTreePath.Slash()'))
    step = nil
    if !Pathname(curr_path).directory?
      step = parts.pop
      # VIM::evaluate('let currentNode = currentNode.parent')
    end
    job = parts.pop
    msg = conn.sdsf_get(job, step)
    if msg == ''
      # VIM::command("call s:echo('Member uploaded')")
      if !Pathname(curr_path).directory?
        VIM::command("call currentNode.open({'where': 'p'})")
        VIM::command("call s:echo('Output retreived')")
      else
        VIM::command('call currentNode.refresh()')
        VIM::command('call currentNode.open()')
        VIM::command('call b:NERDTree.render()')
        VIM::command("call s:echo('Job output list retreived')")
        # VIM::command('redraw')
      end
    else
      VIM::command("call s:echoWarning('#{msg}')")
    end
EOF
  endif
endfunction

function! NERDTreeSDSFDel()
  let currentNode = g:NERDTreeFileNode.GetSelected()
  let zOSNode = s:InZOSFolder(currentNode)
  if !empty(zOSNode)
    " echo 'found'
    " echo zOSNode.path.str()
    ruby << EOF
    zos_path = VIM::evaluate('zOSNode.path.str()')
    curr_path = VIM::evaluate('currentNode.path.str()')
    conn = VIM::ZOS::Connection.new
    conn.load_from_path(zos_path)
    relative_path = curr_path.gsub("#{zos_path}#{VIM::evaluate('g:NERDTreePath.Slash()')}",'')
    parts = relative_path.split(VIM::evaluate('g:NERDTreePath.Slash()'))
    if !Pathname(curr_path).directory?
      parts.pop
    end
    member = parts.pop
    conn.sdsf_del(member)
    sdsf_folder = "#{conn.path}/_spool"
    VIM::command("let newNodeName = '#{sdsf_folder}'")
EOF
    call zOSNode.refresh()
    let newTreeNode = b:NERDTreeRoot.findNode(g:NERDTreePath.New(newNodeName))
    call newTreeNode.putCursorHere(1, 0)
    call NERDTreeRender()
" EOF
"     call zOSNode.refresh()
"     call NERDTreeRender()
    call s:echo('Job deleted')
  endif
endfunction

function! NERDTreeAddFolder()
  let name = input('Input the PDS/folder name: ')
  let currentNode = g:NERDTreeFileNode.GetSelected()
  let zOSNode = s:InZOSFolder2(currentNode)
  if !empty(zOSNode)
    ruby << EOF
    name = VIM::evaluate('name')
    zos_folder = VIM::evaluate('zOSNode.path.str()')
    if !name.include?('/')
      name.gsub!('.','/').upcase!
      parts = name.split('/')
      new_parts = []
      parts.each do |part|
        if part[0] == '$'
          part[0] = '_'
        end
        new_parts << part
      end
      name = parts.join('/')
    end

    dest = "#{zos_folder}/#{name}"
    FileUtils.mkdir_p dest
    # puts "created #{dest}"
EOF
    call zOSNode.refresh()
    call b:NERDTree.render()
    call s:echo('Folder added')
    " redraw
  endif
endfunction

function! NERDTreeGetMember()
  let currentNode = g:NERDTreeFileNode.GetSelected()
  let zOSNode = s:InZOSFolder2(currentNode)
  if !empty(zOSNode)
    " echo 'found'
    " echo zOSNode.path.str()
    ruby << EOF
    zos_path = VIM::evaluate('zOSNode.path.str()')
    curr_path = VIM::evaluate('currentNode.path.str()')
    conn = VIM::ZOS::Connection.new
    conn.load_from_path(zos_path)
    relative_path = curr_path.gsub("#{zos_path}#{VIM::evaluate('g:NERDTreePath.Slash()')}",'')
    parts = relative_path.split(VIM::evaluate('g:NERDTreePath.Slash()'))
    member = parts.pop
    folder = parts.join('/')
    conn.get_member(folder,member)
    VIM::command("call zOSNode.refresh()")
    VIM::command("call b:NERDTree.render()")
    VIM::command("call currentNode.open({'where': 'p'})")
    VIM::command('redraw')
EOF
    call s:echo('Member refreshed')
  endif
endfunction

function! NERDTreePutMember()
  let currentNode = g:NERDTreeFileNode.GetSelected()
  let zOSNode = s:InZOSFolder2(currentNode)
  if !empty(zOSNode)
    " echo 'found'
    " echo zOSNode.path.str()
    ruby << EOF
    zos_path = VIM::evaluate('zOSNode.path.str()')
    curr_path = VIM::evaluate('currentNode.path.str()')
    conn = VIM::ZOS::Connection.new
    conn.load_from_path(zos_path)
    relative_path = curr_path.gsub("#{zos_path}#{VIM::evaluate('g:NERDTreePath.Slash()')}",'')
    parts = relative_path.split(VIM::evaluate('g:NERDTreePath.Slash()'))
    member = parts.pop
    folder = parts.join('/')
    conn.put_member(folder,member, true)
    VIM::command("call zOSNode.refresh()")
    VIM::command("call b:NERDTree.render()")
    VIM::command("call currentNode.open({'where': 'p'})")
    VIM::command('redraw')
EOF
    call s:echo('Member uploaded')
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
      ruby << EOF
      zos_path = VIM::evaluate('zOSNode.path.str()')
      curr_path = VIM::evaluate('currentNode.path.str()')
      conn = VIM::ZOS::Connection.new
      conn.load_from_path(zos_path)
      relative_path = curr_path.gsub("#{zos_path}#{VIM::evaluate('g:NERDTreePath.Slash()')}",'')
      parts = relative_path.split(VIM::evaluate('g:NERDTreePath.Slash()'))
      member = parts.pop
      folder = parts.join('/')
      conn.del_member(folder,member)
      # VIM::command("call currentNode.open({'where': 'p'})")
      # VIM::command('redraw')
EOF
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
    ruby << EOF
    zos_path = VIM::evaluate('zOSNode.path.str()')
    curr_path = VIM::evaluate('currentNode.path.str()')
    conn = VIM::ZOS::Connection.new
    conn.load_from_path(zos_path)
    relative_path = curr_path.gsub("#{zos_path}#{VIM::evaluate('g:NERDTreePath.Slash()')}",'')
    parts = relative_path.split(VIM::evaluate('g:NERDTreePath.Slash()'))
    if !Pathname(curr_path).directory?
      parts.pop
    end
    folder = parts.join('/')
    lines = conn.list_folder(folder)
    index = 0
    page_count = 20
    message = ''
    new_path = ''
    # found = false
    status = 'not found'
    result = ''
    continue = true
    # while lines.count - index > page_count
    while continue
      size = 0
      if lines.count - index > page_count
        size = page_count
      else
        size = lines.count - index
        continue = false
      end
      part = lines[index,page_count]
      i = 0
      part.collect! do |l|
        o = i.to_s.ljust(5) + l + "\n"
        i = i + 1
        index = index + 1
        o
      end
      if continue 
        prompt = part.join + "Please input the member name: (or press ENTER to page through the member list)\n"
      else
        prompt = part.join + "End of list\nPlease input the member name:"
      end

      VIM::command("let result = input('#{prompt}')")
      result = VIM::evaluate('result')
      # puts "result: #{result}"
      if result != ''
        if result[0,1] == "="
          idx = result[1..-1]
          # puts "idx: #{idx}"
          if idx.upcase == 'X'
            # found = true
            status = "canceled"
            break
          end
          idx = idx.to_i
          if folder[0].upcase == folder[0]
            # pds
            if part[0][5,6] == 'Volume'
              result = part[idx][61..-1].strip()
            else
              result = part[idx][5,8].strip()
            end
          else
            # unix
            result = part[idx][59..-1].strip()
          end
        end
        if folder[0].upcase == folder[0]
          # pds
          if part[0][5,6] == 'Volume'
            status = 'folder found'
          else
            status = 'member found'
          end
        else
          # unix
          if part[idx][5,1] == 'd'
            status = "folder found"
          else
            status = "member found"
          end
        end
        # new_path = conn.get_member(folder,result)
        # found = true
        # status = "member found"
        
        break
      end
    end
    if status == "member found"
      continue = true
      while continue
        prompt = "special attributes [0-none]/1-read only/2-ascii/3-1047: "
        VIM::command("let prefix = input('#{prompt}')")
        prefix = VIM::evaluate('prefix')
        case prefix
          when ''
            break
          when '1'
            result = "-read only-#{result}"
            break
          when '2'
            result = "-ascii-#{result}"
            break
          when '3'
            result = "-1047-#{result}"
            break
        end
      end

      prompt = "file suffix: "
      VIM::command("let suffix = input('#{prompt}')")
      suffix = VIM::evaluate('suffix')
      if suffix != ''
        result = "#{result}.#{suffix}"
      end

      new_path = conn.get_member(folder,result)
      VIM::command("let newNodeName = '#{new_path}'")
      VIM::command("call zOSNode.refresh()")
      if Pathname(curr_path).directory?
        VIM::command('call currentNode.open()')
      end
      VIM::command("call b:NERDTree.render()")
      VIM::command("let newTreeNode = b:NERDTreeRoot.findNode(g:NERDTreePath.New(newNodeName))")
      VIM::command("call newTreeNode.putCursorHere(1, 0)")
      VIM::command("call s:echo('Member downloaded')")
    elsif status == "canceled"
      VIM::command("call s:echo('Operation canceled')")
    elsif status == "folder found"
      if !result.include?('/')
        result.gsub!('.','/')
      end
      dest = "#{curr_path}/#{result}"
      FileUtils.mkdir_p dest
      VIM::command("let newNodeName = '#{dest}'")
      VIM::command("call zOSNode.refresh()")
      if Pathname(curr_path).directory?
        VIM::command('call currentNode.open()')
      end
      VIM::command("call b:NERDTree.render()")
      # VIM::command("let newTreeNode = b:NERDTreeRoot.findNode(g:NERDTreePath.New(newNodeName))")
      # VIM::command("call newTreeNode.putCursorHere(1, 0)")
      # puts dest
      VIM::command("call s:echo('Folder added')")
    end
EOF
  endif
endfunction

function! NERDTreeZOSRefreshListener(event)
  let path = a:event.subject
  let action = a:event.action
  let params = a:event.params
  " echo action
  " echo path.str()
  " echo params

  ruby << EOF
  require 'pathname'
  path_name = VIM::evaluate('path.str()')
  found = false
  if Pathname(path_name).directory?
    # puts Pathname(path_name).basename
    if Pathname(path_name).basename.to_s == '_spool'
      # puts 'found _spool'
      VIM::command('call path.flagSet.clearFlags("sdsf")')
      VIM::command('call path.flagSet.addFlag("sdsf", "-SDSF-")')
    else
      Pathname(path_name).each_child do |c|
        if c.basename().to_s == '.zos.connection'
          VIM::command('call path.flagSet.clearFlags("zos")')
          VIM::command('call path.flagSet.addFlag("zos", "-zOS-")')
          found = true
        end
      end
    end
  end
  if !found
    VIM::command('call path.flagSet.clearFlags("zos")')
  end

EOF
endfunction

augroup nerdtreezosplugin
  autocmd BufWritePost * call s:ZOSFileUpdate(expand("%:p"))
augroup END

function! s:ZOSFileUpdate(fname)
  " if exists('g:loaded_syntastic_plugin')
  "   call SyntasticCheck()
  " endif
  "
  " echo a:fname
  if !g:NERDTree.IsOpen()
    return
  endif
  call g:NERDTree.CursorToTreeWin()
  try
    " let node = b:NERDTreeRoot.findNode(g:NERDTreePath.New(a:fname))
    " " echo node.displayString()
    " " echo node.path.str()
    " let node_save = node
    let currentNode = b:NERDTreeRoot.findNode(g:NERDTreePath.New(a:fname))
    let zOSNode = s:InZOSFolder2(currentNode)
    if !empty(zOSNode)
      " echo 'found'
      " echo zOSNode.path.str()
      ruby << EOF
      zos_path = VIM::evaluate('zOSNode.path.str()')
      curr_path = VIM::evaluate('currentNode.path.str()')
      conn = VIM::ZOS::Connection.new
      conn.load_from_path(zos_path)
      relative_path = curr_path.gsub("#{zos_path}#{VIM::evaluate('g:NERDTreePath.Slash()')}",'')
      parts = relative_path.split(VIM::evaluate('g:NERDTreePath.Slash()'))
      member = parts.pop
      folder = parts.join('/')
      msg = conn.put_member(folder,member)
      # puts "msg: #{msg}."
      if msg == ''
        VIM::command("call s:echo('Member uploaded')")
      else
        VIM::command("call s:echoWarning('#{msg}')")
        VIM::command("call zOSNode.refresh()")
        VIM::command("call b:NERDTree.render()")
      end
EOF
    endif
  catch
  endtry

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

ruby << EOF

require 'net/ftp'
require 'fileutils'
require 'yaml'
require 'find'
require 'pathname'
require 'digest'
require 'open3'

module VIM
  module ZOS
    class Connection
      attr_accessor :path, :host, :user, :password
      def initialize
        @path = ''
        @host = ''
        @user = ''
        @password = ''
      end

      def self.add_connection(path, host, user, password)
        if File.exist?(path)
          raise 'Connection folder already exist!'
        end
        FileUtils.mkdir("#{path}")
        file_name = "#{path}/.zos.connection"
        hash = {}
        hash['host'] = host.force_encoding "UTF-8"
        hash['user'] = user.force_encoding "UTF-8"
        hash['password'] = password.force_encoding "UTF-8"
        data = hash.to_yaml
        f = File.open(file_name,'w+')
        f.write(data)
        f.close
      end

      def load_from_path(path)
        @path = path
        file_name = "#{path}/.zos.connection"
        hash = YAML.load(File.read(file_name))
        @host = hash['host']
        @user = hash['user']
        @password = hash['password']
        # puts "loaded from #{file_name}"
      end

      def list_folder(folder)
        # puts "folder : #{folder}"
        if is_pds?(folder)
          parts = folder.split(VIM::evaluate('g:NERDTreePath.Slash()'))
          new_parts = []
          parts.each do |part|
            if part[0] == '_'
              part[0] = '$'
            end
            new_parts << part
          end
          folder = new_parts.join('/')
          folder = "'#{folder.gsub('/','.')}'"
        else
          folder = "/#{folder}"
        end
        Net::FTP.open(@host) do |ftp|
          ftp.passive = true
          ftp.login(@user, @password)
          ftp.chdir(folder)
          return ftp.ls
        end
      end

      def sdsf_list()
        # puts "folder : #{folder}"
        lines = []
        begin
          Net::FTP.open(@host) do |ftp|
            ftp.passive = true
            ftp.login(@user, @password)
            ftp.sendcmd('SITE FILETYPE=JES')
            lines = ftp.ls
          end
        rescue Exception => e
          return e.message
        end
        sdsf_folder = "#{@path}/_spool"
        FileUtils.remove_dir(sdsf_folder, true)
        FileUtils.mkdir_p(sdsf_folder) unless File.exist?(sdsf_folder)
        i = 0
        lines.each do |line|
          # puts line
          job_name = line[0, 8].strip()
          # puts job_name
          if job_name != 'JOBNAME'
            i = i + 1
            job_id = line[9, 8].strip()
            # puts job_id
            job_text = 'x'
            if line[42..-1]
              job_text = line[42..-1].strip()
            end
            if job_text.size == 0
              job_text = 'x'
            end
            # puts job_text
            job_folder = "#{sdsf_folder}/#{i.to_s.rjust(2, '0')}_#{job_name}_#{job_text}_#{job_id}"
            # puts job_folder
            FileUtils.mkdir_p(job_folder)
          end
        end
        # puts 'SDSF list refreshed'
        return sdsf_folder
      end

      def sdsf_get(job, step)
        # puts "deleting #{member}"
        parts = job.split('_')
        job_name = parts[1]
        # puts job_name
        job_id = parts[3]
        # puts job_id
        lines = []
        begin
          Net::FTP.open(@host) do |ftp|
            ftp.passive = true
            ftp.login(@user, @password)
            ftp.sendcmd('SITE FILETYPE=JES')
            if step
              parts = step.split('_')
              step_id = parts[0]
              dest_path = "#{@path}/_spool/#{job}/#{step}"
              src = "#{job_id}.#{step_id}"
              ftp.gettextfile(src, dest_path)
            else
              lines = ftp.list(job_id)
              status = lines[1][27,6]
              # puts "status: #{status}"
              if status == 'OUTPUT'
                lines.each do |line|
                  if line[0, 8] == '        '
                    step_id = line[9, 3].strip()
                    # puts step_id
                    if step_id != 'ID'
                      step_name = line[13,8].strip()
                      # puts step_name
                      proc_step = line[22,8].strip()
                      # puts proc_step
                      dd_name = line[33,8].strip()
                      # puts dd_name
                      mem_name = "#{step_id}_#{dd_name}_#{step_name}"
                      dest_path = "#{@path}/_spool/#{job}/#{mem_name}.txt"
                      src = "#{job_id}.#{step_id}"
                      # puts src
                      # puts dest_path
                      # puts "Retrieving #{dd_name}-#{step_name}"
                      FileUtils.touch(dest_path)
                      # ftp.gettextfile(src, dest_path)
                    end
                  end
                end
              else
                return "#{job_name} - #{job_id} is not in OUTPUT status"
              end
            end
          end
        rescue Exception => e
          return e.message
        end
        return ''
        # puts "#{job_name} - #{job_id} Retrieved"
      end

      def sdsf_del(member)
        # puts "deleting #{member}"
        parts = member.split('_')
        job_name = parts[1]
        # puts job_name
        job_id = parts[3]
        # puts job_id
        begin
          Net::FTP.open(@host) do |ftp|
            ftp.passive = true
            ftp.login(@user, @password)
            ftp.sendcmd('SITE FILETYPE=JES')
            lines = ftp.delete(job_id)
          end
        rescue Exception => e
          return e.message
        end
        job_folder = "#{@path}/_spool/#{member}"
        # puts job_folder
        FileUtils.remove_dir(job_folder, true)
        # puts "#{job_name} - #{job_id} deleted"
      end

      def submit_jcl(relative_path,member)
        src_folder = "#{@path}/#{relative_path}"
        src = "#{src_folder}/#{member}"

        begin
          Net::FTP.open(@host) do |ftp|
            ftp.passive = true
            ftp.login(@user, @password)
            ftp.sendcmd('SITE FILETYPE=JES')
            ftp.puttextfile(src)
          end
        rescue Exception => e
          return e.message
        end
        # puts "Submitted #{src}"
      end

      def get_member(relative_path,member)
        # puts "path #{relative_path}"
        # puts "member #{member}"
        dest_member = member.dup
        if dest_member[0] == '$'
          dest_member[0] = '_'
        end
        encoding = 'IBM-037'
        if member.start_with?('-read only-')
          member = member.gsub('-read only-','')
        end
        if member.start_with?('-ascii-')
          member = member.gsub('-ascii-','')
          encoding = 'ISO8859-1'
        end
        if member.start_with?('-1047-')
          member = member.gsub('-1047-','')
          encoding = 'IBM-1047'
        end
        if member[0] == '_'
          member[0] = '$'
        end
        source_member = member.dup
        src = ''
        if is_pds?(relative_path)
          source_member = member.split('.')[0].upcase
          parts = relative_path.split(VIM::evaluate('g:NERDTreePath.Slash()'))
          new_parts = []
          parts.each do |part|
            if part[0] == '_'
              part[0] = '$'
            end
            new_parts << part
          end
          folder = new_parts.join('/')
          src = "'#{folder.gsub('/','.')}(#{source_member})'"
        else
          src = "/#{relative_path}/#{source_member}"
        end
        dest_folder = "#{@path}/#{relative_path}"
        FileUtils.mkdir_p(dest_folder) unless File.exist?(dest_folder)
        dest = "#{dest_folder}/#{dest_member}"
        # puts "dest: #{dest}"
        # begin
          Net::FTP.open(@host) do |ftp|
            ftp.passive = true
            ftp.login(@user, @password)
            # ftp.sendcmd("SITE SBD=(IBM-1047,ISO8859-1)")
            cmd = "SITE SBD=(#{encoding},ISO8859-1)"
            # puts cmd
            ftp.sendcmd(cmd)
            ftp.gettextfile(src, dest)
          end
        # rescue Exception => e
        #   return e.message
        # end
        backup = "#{dest}.zos.backup"
        diff = "#{dest}.zos.diff"
        # FileUtils.rm(backup) if FileUtils.exist?(backup)        
        FileUtils.cp(dest, backup)
        FileUtils.rm(diff) if File.exist?(diff)
        # create_cksum_file(dest)
        # puts "Downladed to #{dest}"
        return dest
      end

      def del_member(relative_path,member)
        # puts "path #{relative_path}"
        # puts "member #{member}"
        dest_member = member.dup
        if member.start_with?('-read only-')
          member = member.gsub('-read only-','')
        end
        if member.start_with?('-ascii-')
          member = member.gsub('-ascii-','')
        end
        if member.start_with?('-1047-')
          member = member.gsub('-1047-','')
        end
        if member[0] == '_'
          member[0] = '$'
        end
        source_member = member.dup
        src = ''
        if is_pds?(relative_path)
          source_member = member.split('.')[0].upcase
          # src = "'#{relative_path.gsub('/','.')}(#{source_member})'"
          parts = relative_path.split(VIM::evaluate('g:NERDTreePath.Slash()'))
          new_parts = []
          parts.each do |part|
            if part[0] == '_'
              part[0] = '$'
            end
            new_parts << part
          end
          folder = new_parts.join('/')
          src = "'#{folder.gsub('/','.')}(#{source_member})'"
        else
          src = "/#{relative_path}/#{source_member}"
        end
        backup_file = "#{@path}/#{relative_path}/#{member}.zos.backup"
        FileUtils.rm(backup_file) if File.exist?(backup_file)
        begin
          Net::FTP.open(@host) do |ftp|
            ftp.passive = true
            ftp.login(@user, @password)
            ftp.delete(src)
          end
        rescue Exception => e
          return e.message
        end
        return src
      end

      def put_member(relative_path,member, force=false)
        if member.start_with?('-read only-')
          return 'read only, not uploaded'
        end
        if (member.end_with?('.zos.diff') || member.end_with?('.zos.temp'))
          return 'temp file, not uploaded'
        end
        src_folder = "#{@path}/#{relative_path}"
        dest = ''
        encoding = 'IBM-037'
        dest_member = member.dup
        if member.start_with?('-ascii-')
          dest_member = member.gsub('-ascii-','')
          encoding = 'ISO8859-1'
        end
        if member.start_with?('-1047-')
          dest_member = member.gsub('-1047-','')
          encoding = 'IBM-1047'
        end
        if dest_member[0] == '_'
          dest_member[0] = '$'
        end
        if is_pds?(relative_path)
          parts = relative_path.split(VIM::evaluate('g:NERDTreePath.Slash()'))
          new_parts = []
          parts.each do |part|
            if part[0] == '_'
              part[0] = '$'
            end
            new_parts << part
          end
          folder = new_parts.join('/')
          dest = "'#{folder.gsub('/','.')}(#{dest_member.split('.')[0]})'"
        else
          dest = "/#{relative_path}/#{dest_member}"
        end
        src = "#{src_folder}/#{member}"
        # puts "src: #{src}"
        # puts "dest: #{dest}"
        backup_file = "#{src}.zos.backup"
        temp_file = "#{src}.zos.temp"
        diff_file = "#{src}.zos.diff"
        if File.exist?(backup_file) && !force
          # get the file first to compare with the backup
          begin
            Net::FTP.open(@host) do |ftp|
              ftp.passive = true
              ftp.login(@user, @password)
              ftp.sendcmd("SITE SBD=(#{encoding},ISO8859-1)")
              ftp.gettextfile(dest, temp_file)
            end
          rescue Exception => e
            # puts e.message
            # puts e.class
            FileUtils.rm(temp_file) if File.exist?(temp_file)
            return e.message
            # FileUtils.touch(temp_file)
          end
          if FileUtils.identical?(temp_file, backup_file)
            FileUtils.rm(temp_file) if File.exist?(temp_file)
          else
            command = "diff -DVERSION1 '#{temp_file}' '#{backup_file}' > '#{diff_file}'"
            # puts command
            system(command)
            FileUtils.rm(temp_file) if File.exist?(temp_file)
            return "file changed, check the diff file #{diff_file}" 
          end
        end
        begin
          Net::FTP.open(@host) do |ftp|
            ftp.passive = true
            ftp.login(@user, @password)
            ftp.sendcmd("SITE SBD=(#{encoding},ISO8859-1)")
            ftp.puttextfile(src, dest)
            # puts 'upload: ' + src
          end
        rescue Exception => e
          return e.message
        end
        # puts "Uploaded to #{dest}"
        # FileUtils.rm(backup_file) if FileUtils.exist?(backup_file)        
        begin
          Net::FTP.open(@host) do |ftp|
            ftp.passive = true
            ftp.login(@user, @password)
            ftp.sendcmd("SITE SBD=(#{encoding},ISO8859-1)")
            ftp.gettextfile(dest, backup_file)
            # puts "got: #{backup_file}"
          end
        rescue Exception => e
          return e.message
        end
        FileUtils.rm(diff_file) if File.exist?(diff_file)
        # FileUtils.cp(src, backup_file)
        # create_cksum_file(src)
        return ''
      end

      private
      def is_pds?(folder)
        return folder[0].upcase == folder[0]
      end

    end
  end
end

EOF

