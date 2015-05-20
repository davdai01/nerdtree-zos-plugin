" rubyfile ./zos_explorer.rb
if exists('g:loaded_nerdtree_zos')
  finish
endif
let g:loaded_nerdtree_zos = 1

let NERDTreeIgnore = ['\.zos.connection$']
call NERDTreeAddMenuSeparator()
call NERDTreeAddMenuItem({'text': '(z) Add a z/OS Connection', 'shortcut': 'z', 'callback': 'NERDTreeAddConnection'})
call NERDTreeAddMenuItem({'text': '(f) Add a PDS/folder', 'shortcut': 'f', 'isActiveCallback': 'NERDTreezOSEnabled', 'callback': 'NERDTreeAddFolder'})
call NERDTreeAddMenuItem({'text': '(l) List members', 'shortcut': 'l', 'isActiveCallback': 'NERDTreezOSEnabled',  'callback': 'NERDTreeListMembers'})

function! NERDTreezOSEnabled()
  let currentNode = g:NERDTreeFileNode.GetSelected()
  let zOSNode = s:InZOSFolder(currentNode)
  if !empty(zOSNode)
    return 1
  endif
  return 0
endfunction

com! JCLSubmit call SubJCL(expand("%:p"))
function! SubJCL(fname)
  call g:NERDTree.CursorToTreeWin()
  " try
    let node = b:NERDTreeRoot.findNode(g:NERDTreePath.New(a:fname))
    let zOSNode = s:InZOSFolder(node)
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
endfunction

function! NERDTreeAddFolder()
  let name = input('Input the PDS/folder name: ')
  let currentNode = g:NERDTreeFileNode.GetSelected()
  let zOSNode = s:InZOSFolder(currentNode)
  if !empty(zOSNode)
    ruby << EOF
    name = VIM::evaluate('name')
    zos_folder = VIM::evaluate('zOSNode.path.str()')
    if !name.include?('/')
      name.gsub!('.','/').upcase!
    end
    dest = "#{zos_folder}/#{name}"
    FileUtils.mkdir_p dest
    puts "created #{dest}"
EOF
  endif
endfunction

function! NERDTreeListMembers()
  let currentNode = g:NERDTreeFileNode.GetSelected()
  " echo 'current node'
  " echo currentNode.path.str()
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
    folder = parts.join('/')
    lines = conn.list_folder(folder)
    index = 0
    page_count = 20
    message = ''
    found = false
    while lines.count - index > page_count
      part = lines[index,page_count]
      part.collect! do |l|
        o = index.to_s.ljust(5) + l + "\n"
        index = index + 1
        o
      end
      prompt = part.join + "Please input the member name: (or press ENTER to page through the member list)\n"
      VIM::command("let result = input('#{prompt}')")
      result = VIM::evaluate('result')
      puts "result: #{result}"
      if result != ''
        conn.get_member(folder,result)
        found = true
        break
      end
    end
    if !found
      part = lines[index,lines.count-index]
      part.collect! do |l|
        o = index.to_s.ljust(5) + l + "\n"
        index = index + 1
        o
      end
      prompt = part.join + "End of list\nPlease input the member name:"
      VIM::command("let result = input('#{prompt}')")
      result = VIM::evaluate('result')
      # puts "result: #{result}"
      if result != ''
        conn.get_member(folder,result)
      end
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
  if Pathname(path_name).directory?
    found = false
    Pathname(path_name).each_child do |c|
    if c.basename().to_s == '.zos.connection'
      VIM::command('call path.flagSet.clearFlags("zos")')
      VIM::command('call path.flagSet.addFlag("zos", "-zOS-")')
      found = true
    end
  end
  if !found
    VIM::command('call path.flagSet.clearFlags("zos")')
  end
end
EOF
endfunction

augroup nerdtreezosplugin
  autocmd!
  autocmd BufWritePost * call s:ZOSFileUpdate(expand("%:p"))
augroup END

function! s:ZOSFileUpdate(fname)
  " echo a:fname
  if !g:NERDTree.IsOpen()
    return
  endif
  call g:NERDTree.CursorToTreeWin()
  try
    let node = b:NERDTreeRoot.findNode(g:NERDTreePath.New(a:fname))
    " echo node.displayString()
    " echo node.path.str()
    let node_save = node
    let node = node.parent
    while !empty(node)
      " echo node.displayString()
      " echo node.path.str()
      ruby << EOF
      path_string = VIM::evaluate('node.displayString()')
      if path_string.include?('[-zOS-]')
        # echo node.path.str()
          path_save = VIM::evaluate('node_save.path.str()')
          path = VIM::evaluate('node.path.str()')
          relative_path = path_save.gsub("#{path}#{VIM::evaluate('g:NERDTreePath.Slash()')}",'')
          # puts "relative_path: #{relative_path}"
          conn = VIM::ZOS::Connection.new
          conn.load_from_path(path)
          parts = relative_path.split(VIM::evaluate('g:NERDTreePath.Slash()'))
          member = parts.pop
          folder = parts.join('/')
          conn.put_member(folder,member)
      end
EOF
      let node = node.parent
    endwhile
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

autocmd FileType nerdtree call s:AddHighlighting()
function! s:AddHighlighting()
  syn match NERDTreezOS #\[-zOS-\]#
  hi def link NERDTreezOS statement
endfunction

call g:NERDTreePathNotifier.AddListener("init", "NERDTreeZOSRefreshListener")
call g:NERDTreePathNotifier.AddListener("refresh", "NERDTreeZOSRefreshListener")
call g:NERDTreePathNotifier.AddListener("refreshFlags", "NERDTreeZOSRefreshListener")

ruby << EOF

require 'net/ftp'
require 'FileUtils'
require 'yaml'
require 'find'
require 'pathname'

module VIM
  module ZOS
    class Connection
      attr_accessor :path, :host, :user, :password
      def initialize
        @path = ''
        @host = 'FTS1'
        @user = 'DXD'
        @password = 'POLYCOM'
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
        puts "loaded from #{file_name}"
      end

      def list_folder(folder)
        # puts "folder : #{folder}"
        if is_pds?(folder)
          folder = "'#{folder.gsub('/','.')}'"
        else
          folder = "/#{folder}"
        end
        Net::FTP.open(@host) do |ftp|
          ftp.login(@user, @password)
          ftp.chdir(folder)
          return ftp.ls
        end
      end

      def submit_jcl(relative_path,member)
        src_folder = "#{@path}/#{relative_path}"
        src = "#{src_folder}/#{member}"

        Net::FTP.open(@host) do |ftp|
          ftp.login(@user, @password)
          ftp.sendcmd('SITE FILETYPE=JES')
          ftp.puttextfile(src)
        end
        puts "Submitted #{src}"
      end

      def get_member(relative_path,member)
        puts "path #{relative_path}"
        puts "member #{member}"
        src = ''
        if is_pds?(relative_path)
          src = "'#{relative_path.gsub('/','.')}(#{member})'"
          member.upcase!
        else
          src = "/#{relative_path}/#{member}"
        end
        dest_folder = "#{@path}/#{relative_path}"
        FileUtils.mkdir_p(dest_folder) unless File.exist?(dest_folder)
        dest = "#{dest_folder}/#{member}"
        puts "dest: #{dest}"
        Net::FTP.open(@host) do |ftp|
          ftp.login(@user, @password)
          ftp.gettextfile(src, dest)
        end
        puts "Downladed to #{dest}"
      end

      def put_member(relative_path,member)
        src_folder = "#{@path}/#{relative_path}"
        dest = ''
        if is_pds?(relative_path)
          dest = "'#{relative_path.gsub('/','.')}(#{member.split('.')[0]})'"
        else
          dest = "/#{relative_path}/#{member}"
        end
        src = "#{src_folder}/#{member}"
        # puts "src: #{src}"
        # puts "dest: #{dest}"
        Net::FTP.open(@host) do |ftp|
          ftp.login(@user, @password)
          ftp.puttextfile(src, dest)
        end
        puts "Uploaded to #{dest}"
      end
      def is_pds?(folder)
        return folder[0].upcase == folder[0]
      end
    end
  end
end

EOF

