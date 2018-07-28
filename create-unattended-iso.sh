#!/usr/bin/env bash

# file names & paths
pwd=`pwd`
tmp=$pwd/tmp  # destination folder to store the final iso file
mkdir $tmp >/dev/null 2>&1
currentuser="$( whoami)"

# define spinner function for slow tasks
# courtesy of http://fitnr.com/showing-a-bash-spinner.html
spinner()
{
    local pid=$1
    local delay=0.75
    local spinstr='|/-\'
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

# define download function
# courtesy of http://fitnr.com/showing-file-download-progress-using-wget.html
download()
{
    local url=$1
    echo -n "    "
    wget --progress=dot $url 2>&1 | grep --line-buffered "%" | \
        sed -u -e "s,\.,,g" | awk '{printf("\b\b\b\b%4s", $2)}'
    echo -ne "\b\b\b\b"
    echo " DONE"
}

# print a pretty header
echo
echo " +---------------------------------------------------+"
echo " |            UNATTENDED UBUNTU ISO MAKER            |"
echo " +---------------------------------------------------+"
echo

# ask if script runs without sudo or root priveleges
if [ $currentuser != "root" ]; then
    echo " you need sudo privileges to run this script, or run it as root"
    exit 1
fi

#check that we are in ubuntu 16.04+

case "$(lsb_release -rs)" in
    16*|18*) ub1604="yes" ;;
    *) ub1604="" ;;
esac

#get the latest versions of Ubuntu LTS

tmphtml=$tmp/tmphtml
rm $tmphtml >/dev/null 2>&1
wget -O $tmphtml 'http://releases.ubuntu.com/' >/dev/null 2>&1

prec=$(fgrep Precise $tmphtml | head -1 | awk '{print $3}')
trus=$(fgrep Trusty $tmphtml | head -1 | awk '{print $3}')
xenn=$(fgrep Xenial $tmphtml | head -1 | awk '{print $3}')
bion=$(fgrep Bionic $tmphtml | head -1 | awk '{print $3}')

# ask whether to include vmware tools or not
while true; do
    echo " which ubuntu edition would you like to remaster:"
    echo
    echo "  [1] Ubuntu $prec LTS Server amd64 - Precise Pangolin"
    echo "  [2] Ubuntu $trus LTS Server amd64 - Trusty Tahr"
    echo "  [3] Ubuntu $xenn LTS Server amd64 - Xenial Xerus"
    echo "  [4] Ubuntu $bion LTS Server amd64 - Bionic Beaver"
    echo
    read -p " please enter your preference: [1|2|3|4]: " ubver
    case $ubver in
        [1]* )  download_file="ubuntu-$prec-server-amd64.iso"           # filename of the iso to be downloaded
                download_location="http://releases.ubuntu.com/$prec/"     # location of the file to be downloaded
                new_iso_name="ubuntu-$prec-server-amd64-unattended.iso" # filename of the new iso file to be created
                break;;
        [2]* )  download_file="ubuntu-$trus-server-amd64.iso"             # filename of the iso to be downloaded
                download_location="http://releases.ubuntu.com/$trus/"     # location of the file to be downloaded
                new_iso_name="ubuntu-$trus-server-amd64-unattended.iso"   # filename of the new iso file to be created
                break;;
        [3]* )  download_file="ubuntu-$xenn-server-amd64.iso"
                download_location="http://releases.ubuntu.com/$xenn/"
                new_iso_name="ubuntu-$xenn-server-amd64-unattended.iso"
                break;;
        [4]* )  download_file="ubuntu-$bion-server-amd64.iso"
                download_location="http://cdimage.ubuntu.com/releases/$bion/release/"
                new_iso_name="ubuntu-$bion-server-amd64-unattended.iso"
                break;;
        * ) echo " please answer [1], [2], [3] or [4]";;
    esac
done

# download the ubunto iso. If it already exists, do not delete in the end.
cd $tmp
if [[ ! -f $tmp/$download_file ]]; then
    echo -n " downloading $download_file: "
    download "$download_location$download_file"
fi
if [[ ! -f $tmp/$download_file ]]; then
        echo "Error: Failed to download ISO: $download_location$download_file"
        echo "This file may have moved or may no longer exist."
        echo
        echo "You can download it manually and move it to $tmp/$download_file"
        echo "Then run this script again."
        exit 1
fi

# create working folders
echo " remastering your iso file"
mkdir -p $tmp
mkdir -p $tmp/iso_org
mkdir -p $tmp/iso_new

# mount the image
if grep -qs $tmp/iso_org /proc/mounts ; then
    echo " image is already mounted, continue"
else
    (mount -o loop $tmp/$download_file $tmp/iso_org > /dev/null 2>&1)
fi

# copy the iso contents to the working directory
(cp -rT $tmp/iso_org $tmp/iso_new > /dev/null 2>&1) &
spinner $!

# set the language for the installation menu
cd $tmp/iso_new
#doesn't work for 16.04
echo en > $tmp/iso_new/isolinux/lang

#16.04
#taken from https://github.com/fries/prepare-ubuntu-unattended-install-iso/blob/master/make.sh
sed -i -r 's/timeout\s+[0-9]+/timeout 1/g' $tmp/iso_new/isolinux/isolinux.cfg

# copy the netson seed file to the iso
if ! cp -rT $pwd/brainforge.seed $tmp/iso_new/preseed/brainforge.seed
then
  exit 1
fi

# calculate checksum for seed file
seed_checksum=$(md5sum $tmp/iso_new/preseed/brainforge.seed)

# add the autoinstall option to the menu
sed -i "/label install/ilabel autoinstall\n\
  menu label ^Autoinstall NETSON Ubuntu Server\n\
  kernel /install/vmlinuz\n\
  append file=/cdrom/preseed/ubuntu-server.seed initrd=/install/initrd.gz auto=true priority=high preseed/file=/cdrom/preseed/brainforge.seed preseed/file/checksum=$seed_checksum --" $tmp/iso_new/isolinux/txt.cfg

echo " creating the remastered iso"
cd $tmp/iso_new
(mkisofs -D -r -V "NETSON_UBUNTU" -cache-inodes -J -l -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -o $tmp/$new_iso_name . > /dev/null 2>&1) &
spinner $!

# cleanup
umount $tmp/iso_org
rm -rf $tmp/iso_new
rm -rf $tmp/iso_org
rm -rf $tmphtml


# print info to user
echo " -----"
echo " finished remastering your ubuntu iso file"
echo " the new file is located at: $tmp/$new_iso_name"
echo

# unset vars
unset download_file
unset download_location
unset new_iso_name
unset tmp
