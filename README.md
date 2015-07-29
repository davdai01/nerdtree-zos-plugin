nerdtree-zos-plugin
===================

A plugin of NERDTree for editing files from IBM mainframe z/OS system. Works with the **LATEST** version
of [NERDTree](https://github.com/scrooloose/nerdtree).

## Requirements
* Vim 7.0+ with +ruby or +ruby/dyn
* Ruby 1.9+
* z/OS FTP server

## Installation

[Vundle.vim](https://github.com/VundleVim/Vundle.vim) is recommended to use for
installing nerdtree-zos-plugin

`Plugin 'scrooloose/nerdtree'`

`Plugin 'davdai01/nerdtree-zos-plugin'`

## Usage

The following functions are added to NERDTree menu:
```
--------------------
(z) Add a z/OS Connection
(f) Add a PDS/folder
(l) List members
```

* You can add a connection to z/OS FTP server, once done, you will see a folder
  created for the connection and the folder is having a *[-zOS-]* tag
* Add a PDS or Unix folder from your mainframe z/OS system, and this will be mapped
  to a local folder in your [-zOS-] connection folder
* Use *(L) list member* function to list through members in the PDS or folder, and choose to edit a
  member file
* You can then edit the file, and the changes will be automatically uploaded to
  mainframe whenever you save it in Vim
* if you are editing JCL file, you can submit this directly to mainframe from
  Vim using command :JCLSubmit

