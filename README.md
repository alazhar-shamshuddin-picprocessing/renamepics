# renamepics
Provides services to rename (and renumber) picture and movie files in a given
directory so that they adhere to a prescribed naming convention.

## Quick Start
Refer to the 
[PicProcessing/Docker Git Repository](https://github.com/alazhar-shamshuddin-picprocessing/docker).
It contains:
1. A copy of some Perl modules that are required by all picprocessing apps.
2. A [Dockerfile](https://github.com/alazhar-shamshuddin-picprocessing/docker/blob/main/Dockerfile)
with detailed comments.  You may run any picprocessing app (including 
renamepics.pl) through docker or independently on your host machine.  The
Dockerfile contains the commands you would enter on your host machine to
run the app outside of docker.

## Installation Instructions
To ensure renamepics.pl runs on your host machine, follow the steps below
(or the commands in the 
[Dockerfile](https://github.com/alazhar-shamshuddin-picprocessing/docker/blob/main/Dockerfile)
referenced above):
1.  Download cpanm:

    `curl -L https://cpanmin.us | perl - --sudo App::cpanminus` 

    cpanm is also available in the default software repositories of several 
    Linux distributions although it may be a bit older than what is available
    via https://cpanmin.us.  You may install that version of cpanm using the
    following command instead of the one above:

    `sudo apt install cpanminus`

1. Install the required modules:

    `sudo cpanm Image::ExifTool`

    `sudo cpanm Log::Log4perl`

    Depending on your environment, you may need install additional Perl modules.

1. Make the Perl file executable:

    `chmod u+x renamepics.pl`

1. Optionally, copy the app to a folder in your PATH (e.g., ~/.local/bin)
   and remove the extension from the filename.  You can then run the the app
   from anywhere on your system:

    `renamepics -h`