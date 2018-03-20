# rsyncshot
A posix compliant shell script for creating rotating backups based on rsync.
(including backing up remote machines [running rsyncd/sshd] to local destinations)

** Please read the rsyncshot_readme file for documentation

***Motivation***
1) I wanted to backup configurations and data of various virtual machines I run, and wanted to have the job done by a free tool which does not require installation (like for example rsnapshot). I wanted a simple copy and run script.
2) I enjoy scripting, so I wanted decided:
    a) to have a POSIX compliant script (judged by shellcheck.net)
    b) refrain from using external utilities like awk, sed, etc. (although even the "test" program could be considered external) and despite the fact that such approach would make some otherwise easy tasks in bash much cumbersome to program in pure sh
    c) have a proper sanity checks on filenames
    d) provide a source for others to use / learn from
PS: I'm not a programmer. It's my hobby, so feel free to submit improvements.
    
***Installation***

  Copy the script to a destination of your choosing and then run according to the readme.
  
  Please make sure you have sufficient rights to read/write data.

***Features***
  
  See rsyncshot_readme, but in a nutshell:
  a. posic compliant
  b. multiple source/destination pairs per backup job
  c. possibility to use config files
  d. remote backups from machines either via rsync or ssh protocols
  e.  auto cron-job creation
  
***To Do / Still open***
  1. Multiple jobs per config file (currently only one job per config file is supported)
  2. Extensive testing... (script works ok on my machines)

**OPEN FOR CONTRIBUTORS(!)**

  Instead of forking, I am happy to grant an access to you if you find the script useful and would like to contribute to its features.

***Credits***

  to be done.
