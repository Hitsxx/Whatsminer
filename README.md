1. First, edit upgrade-files/ to select what to be upgraded.

2. Then, run make-package.sh to generate upgrade package.

  $ ./make-package.sh
  Generated package:  whatsminer-$MACHINE_TYPE-$VERSION_NUMBER-upgrade.zip

  The generated package contains three files:

    - remote-upgrade.sh
    - upgrade-$MACHINE_TYPE-$VERSION_NUMBER.tgz
    - HOWTO

2. Prepare Miners IP list file ip.txt to be upgraded (one IP per line):

   $ cat ip.txt
   192.168.1.10
   192.168.1.11
   ..

3. Run remote-upgrade.sh to upgrade miners.

  $ ./remote-upgrade.sh upgrade-$MACHINE_TYPE-$VERSION_NUMBER.tgz ip.txt

  Enjoy it.
