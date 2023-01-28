#!/bin/bash

# ----------------------------------------------
# Script to automatically install linux dotfiles
# Author: Desktop31
# 
# Inspired by https://larbs.xyz/
# ----------------------------------------------



# ============================
#     FUNCTION DEFINITIONS
# ============================

# Styles variables for printf
BOLD='\033[1m'
RED='\033[31m'
RESET='\033[0m'


# Print usage duh
help() {
	echo "Usage:"
	echo "	$0 --user=<username> (--wayland | --xorg) [--packages=<package-list>]"
	echo ""
	echo "Options:"
	echo "	-u | --user 			username"
	echo "	-w | --wayland 			install wayland packages (hyprland + waybar)"
	echo "	-x | --xorg			install xorg packages (dwm + polybar)"
	echo "	-p | --packages 		extra packages to install (standard, extra)"
	echo ""
	echo "Example: "
	echo "	$0 --user=desktop31 --wayland --xorg --packages=standard,extra  "
	echo ""
}


error() {
	printf "%s\n" "$1" >&2
	exit 1
}


# Parse arguments from $1 to variables
parseArgs() {
	# Set $N arguments to $1 values ($1=--user $2=<user> ...)
	eval set -- "$1"
	
	while :
	do
		case "$1" in
			-u | --user )
				# convert to lowercase and assign to variable
				user=$(echo "$2" | tr '[:upper:]' '[:lower:]')

				local check=$(echo "$user" | grep "^[a-z_][a-z0-9_-]*$")
				if [[ $check != $user ]]; then
					error "Invalid username format."
				fi
				# move to the next argument 
				# (shift 1 = next option name, shift 2 = next argument)
				shift 2 
				;;
			-w | --wayland )
				PKGS=("wayland" "${PKGS[@]}")
				shift 1
				;;
			-x | --xorg )
				PKGS=("xorg" "${PKGS[@]}")
				shift 1
				;;
			-p | --packages )
				if [[ -n $2 ]]; then
					local pkgs=()
					IFS=, read -r -a pkgs <<< "$2"
					PKGS=("${PKGS[@]}" "${pkgs[@]}")
				fi
				shift 2
				;;
			-h | --help )
				help
				exit 0
				;;
			-- )
				shift;
				break;
				;;
			* )
				echo "Unexpected argument: $1"
				exit 2
				;;
		esac
	done
}


# Check if user with name $1 already exists
# If user exists, return 1, else 0
checkUser() {
	local userID="$(id -u $1 2>>/dev/null)"
	if [[ $userID -ne 0 ]]; then
		return 1
	else
		return 0
	fi
}

# Ask for password and create user with name $1
createUser() {
	if [[ -z $1 ]]; then
		error "Aborting - no username entered."
	fi

	checkUser $1

	if [[ $? == 1 ]]; then
		whiptail --title "WARNING" --yes-button "CONTINUE" \
			--no-button "ABORT" \
			--yesno "User '$1' already exists.\\n\\nIf you continue, some user settings and files may be overwritten." \
			10 70
			
		if [[ $? == 1 ]]; then
			error "Instalation aborted by user."
		else
			return 0
		fi
	fi

	local passw1=$(whiptail --nocancel --passwordbox "Enter a password for user '$1':" 10 70 3>&1 1>&2 2>&3 3>&1)
	local passw2=$(whiptail --nocancel --passwordbox "Retype password:" 10 70 3>&1 1>&2 2>&3 3>&1)

	while [[ $passw1 != $passw2 ]]; do
		passw1=$(whiptail --nocancel --passwordbox "Passwords do not match.\n\nEnter a password for user '$1':" 10 70 3>&1 1>&2 2>&3 3>&1)
		passw2=$(whiptail --nocancel --passwordbox "Retype password:" 10 70 3>&1 1>&2 2>&3 3>&1)
	done

	echo "Creating user '$1'..."
	useradd -m -g wheel -s /bin/zsh "$1" >/dev/null 2>&1 
	if [[ $? -ne 0 ]]; then
		return 1
	fi
	
	echo "$1:$passw1" | chpasswd 
	unset passw1 passw2
}


refreshKeys() {
	echo "Refreshing archlinux keyring..."
	pacman --noconfirm -S archlinux-keyring >>/dev/null 2>&1
}

syncTime() {
	echo "Syncing time..."
	ntpd -q -g >/dev/null 2>&1
}

# Clone dotfile repository to user's home directory
cloneRepo() {
	echo "Preparing to clone dotfile repository..."
	
	mkdir -p "$SOURCEDIR"
	chown -R "$user":wheel "$SOURCEDIR"

	# Clone dotfiles
	sudo -u "$user" git -C "$SOURCEDIR" clone --depth 1 \
			--single-branch --no-tags -q --recursive -b "$REPOBRANCH" \
			--recurse-submodules "$REPO" "$SOURCEDIR/dotfiles"

	if [[ -d "$SOURCEDIR/dotfiles" ]]; then
		echo "Repository cloned successfully."
	else
		return 1
	fi
}


# Guess what this does
installAURHelper() {
	echo "Installing AUR Helper ('$HELPERCMD')"
	
	sudo -u "$user" git -C "$SOURCEDIR" clone --depth 1 \
				--single-branch --no-tags -q "$HELPERREPO" "$SOURCEDIR/$HELPERCMD"
				
	cd "$SOURCEDIR/$HELPERCMD" 
	sudo -u "$user" -D "$SOURCEDIR/$HELPERCMD" makepkg --noconfirm -si >>/dev/null 2>&1 || return 1
	cd "$SCRIPTDIR"
}

# Using pacman, install package $1 from list $2 which is $3st/nd/rd/th of $4
pacmanInstall() {
	printf "${BOLD}pacman:${RESET} [$3/$4] Installing package: [$2] '$1'\n"
	pacman --noconfirm --needed -S $1 >>/dev/null 2>&1 
	if [ $? -ne 0 ]; then printf "${RED}${BOLD}pacman:${RESET}${RED} Failed to install package [$2] '$1'${RESET}\n" | tee -a "$ERRFILE"; fi
}

# Using aur helper, install package $1 from list $2 which is $3st/nd/rd/th of $4
aurInstall() {
	printf "${BOLD}$HELPERCMD:${RESET} [$3/$4] Installing package: [$2] '$1'\n"
	sudo -u "$user" $HELPERCMD --noconfirm --needed -S $1 >>/dev/null 2>&1 
	if [ $? -ne 0 ]; then printf "${RED}${BOLD}$HELPERCMD:${RESET}${RED} Failed to install package [$2] '$1'${RESET}\n" | tee -a "$ERRFILE"; fi
}

# Pulls git repository $1 and compiles it using make 
gitMakeInstall() {
	local name="$(basename $1)"
	name="${name%.git}"

	printf "${BOLD}git:${RESET} [$3/$4] Pulling repository: [$2] '$1'\n"
	sudo -u "$user" git -C "$SOURCEDIR" clone --depth 1 --single-branch --recursive --no-tags -q "$1" "$SOURCEDIR/$name" || 
		{
			cd "$SOURCEDIR/$name" || return 1
			printf "${BOLD}git:${RESET} [$3/$4] Directory already exists, attempting to update...\n"
			sudo -u "$user" git pull 
		}
	
	cd "$SOURCEDIR/$name" ||  return 1
	printf "${BOLD}git:${RESET} [$3/$4] Repository downloaded successfully, running ${BOLD}'make'${RESET}...\n"
	
	make >>/dev/null 2>&1 
	if [[ $? -ne 0 ]]; then
		printf "${RED}${BOLD}git:${RESET}${RED} Failed to make [$2] '$name'${RESET}\n" | tee -a "$ERRFILE"
		return 1
	fi
	make install >>/dev/null 2>&1 
	if [[ $? -ne 0 ]]; then
		printf "${RED}${BOLD}git:${RESET}${RED} Failed to make install [$2] '$name'${RESET}\n" | tee -a "$ERRFILE"
		return 1
	fi

	printf "${BOLD}git:${RESET} [$3/$4] Successfully installed '$name'.\n"
	cd "$SCRIPTDIR"
}


# Install packages from string in format: "xclip bluez ..."
# $1 is the array, 
# $2 is the title of the array/description
# $3 is the way to install [P = pacman, A = AUR, G = git,make]
installPackageArray() {
	local total="$(echo $1 | wc -w)"
	local name="$2"

	declare -A type
	type[P]="pacmanInstall"
	type[A]="aurInstall"
	type[G]="gitMakeInstall"
	
	if [[ $# -ne 3 || -z "${type[$3]}" ]]; then
		printf "${BOLD}Error:${RESET} Could not install packages: $1\n"
		return
	fi

	local i=1
	for pkg in $1; do
		"${type[$3]}" "$pkg" "$name" "$i" "$total"
		i=$((i + 1))
	done
}


# Install packages marked as pacman (= not marked) from a file $1
# Valid package list file format:
# pkg-name
# pkg-name 
pacmanInstallFile() {
	local list="$(cat $1 | awk '!/^.*[AG]$/{print $1}')"
	installPackageArray "$list" "$(basename $1)" "P"
}

# Install packages marked as aur (= "A" at the end) from a file $1
# Valid package list file format:
# pkg-name	A
# pkg-name	A
aurInstallFile() {
	local list="$(cat $1 | awk '/^.*A$/{print $1}')"
	installPackageArray "$list" "$(basename $1)" "A"
}

# Install packages marked as git (= "G" at the end) from a file $1
# Valid package list file format:
# pkg-name	G
# pkg-name	G
gitInstallFile() {
	local list="$(cat $1 | awk '/^.*G$/{print $1}')"
	installPackageArray "$list" "$(basename $1)" "G"
}


# Install all packages from file $1, files are in directory $2
# $1 ... array of lists of packages like: ('xorg', 'wayland', ...)
installPackages() {
	for list in "${PKGS[@]}"; do
		local path="$PKGDIR/$list"
		if [[ -f $path ]]; then
			pacmanInstallFile "$path"
			aurInstallFile "$path"
			gitInstallFile "$path"
		fi
	done
}


# Copy files from directory $1 in dotfiles to $2
copyDirContent() {
	echo "Copying files from directory '$1' to '$2'"

	local dirPath="$SOURCEDIR/dotfiles/$1"
	
	if [[ ! -d $2 ]]; then
		mkdir -p $2 
	fi

	cp -rT "$dirPath" "$2" 

	local isUserDir="$(echo "$2" | grep "/home/$user/")"
	if [[ -n $isUserDir ]]; then
		chown -R "$user":wheel "$2"
	fi
}

# Copy file $1 from dotfiles to home directory
copyHome() {
	echo "Copying file '$1' to '/home/$user/'"
	sudo -u $user cp "$SOURCEDIR/dotfiles/$1" "/home/$user/$1" 
}

# Unpack compressed files from directory $1 in dotfiles to $2
unpackFiles() {
	echo "Unpacking compressed files from '$1' to '$2'..."
	local dirPath="$SOURCEDIR/dotfiles/$1"

	local files=()
	IFS=" " read -r -a files <<< "$(ls -1 $dirPath | grep ".*\.tar.*" | tr '\n' ' ')"

	if [[ "${#files[@]}" -ne 0 && ! -d $2 ]]; then
		mkdir -p $2
	fi

	for file in "$files"; do
		case "$file" in
			*.tar.gz | *.tgz )
				tar -xzf "$dirPath/$file" -C "$2" >>/dev/null 2>&1
				;;
			*.tar.bz | *.tar.bz2 | *.tbz | *.tbz2 )
				tar -xjf "$dirPath/$file" -C "$2" >>/dev/null 2>&1
				;;
			*.tar.xz | *.txz )
				tar -xJf "$dirPath/$file" -C "$2" >>/dev/null 2>&1
				;;
			*.zip )
				unzip "$dirPath/$file" -d "$2" >>/dev/null 2>&1
				;;
			* )
				echo "Could not extract file '$file'"
				;;
		esac
	done
}



# =======================
# 	  PARSE ARGUMENTS
# =======================

# Define and get valid user arguments
SHORT=u:,w,x,p:,h
LONG=user:,wayland,xorg,packages:,help
OPTS=$(getopt --alternative --name $0 --options $SHORT --longoptions $LONG -- "$@") 

# Check if getopt was successful
if [[ $? -ne 0 ]]; then
	exit 1
fi


# =====================
#     INITIAL SETUP
# =====================

# Dotfiles repository to clone
REPO="https://github.com/Desktop31/dotfiles.git"
REPOBRANCH="main"

# AUR Helper repository
HELPERREPO="https://aur.archlinux.org/yay.git"
HELPERCMD="yay"

# Default packages
PKGS=('base' 'fonts')

# Parse arguments to variables
parseArgs "$OPTS"

# Directory to put dotfiles in and install stuff from source
SOURCEDIR="/home/$user/.local/src"

# Directory where this script is located
SCRIPTDIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# Package list directory
PKGDIR="$SCRIPTDIR/pkgs" 

# Stuff that went bad goes here
ERRFILE="$SCRIPTDIR/err.txt"



# ===================
#      EXECUTION 
# ===================

# Check if user is root on Arch distro, install whiptail.
pacman --noconfirm --needed -Sy libnewt || error "Error installing whiptail. Make sure to run this script as root on an Arch based system connected to the internet."

# Refresh archlinux keyring
refreshKeys || error "Error refreshing archlinux keyring."

# Install packages required for deployment
installPackageArray "curl ca-certificates base-devel git ntp zsh unzip tar sudo" "dependencies" "P"

# I wonder what this does
syncTime

# Ask for password and create user
createUser "$user" || error "Could not create user."

# Clone dotfile repository to $SOURCEDIR
cloneRepo || error "Error cloning repository."


# Allow user to run sudo without password (required for AUR installations)
printf "\n${BOLD}-- PREPARING FOR INSTALLATION --${RESET}\n"
trap 'rm -f /etc/sudoers.d/autoinstall-temp' HUP INT QUIT TERM PWR EXIT
echo "%wheel ALL=(ALL) NOPASSWD: ALL" >/etc/sudoers.d/autoinstall-temp

# Allow concurrent downloads
sed -Ei "s/^#(ParallelDownloads).*/\1 = 5/#//" /etc/pacman.conf

# Enable multilib repository
sed -Ei "/\[multilib\]/,/Include/"'s/^#//' /etc/pacman.conf
# Update database
pacman --noconfirm --needed -Sy >>/dev/null 2>&1

# Use all cores for compilation.
sed -i "s/-j2/-j$(nproc)/;/^#MAKEFLAGS/s/^#//" /etc/makepkg.conf

# Get rid of beep
rmmod pcspkr
echo "blacklist pcspkr" >/etc/modprobe.d/nobeep.conf

# Install AUR helper defined in $HELPERREPO and $HELPERCMD
installAURHelper


# Create user directories and copy content from dotfiles
printf "\n${BOLD}-- COPYING CONFIGURATION FILES --${RESET}\n"

installPackageArray "xdg-user-dirs" "configs" "P"
xdg-user-dirs-update >>/dev/null 2>&1
copyDirContent "Pictures" "/home/$user/Pictures"
copyDirContent "Pictures/Wallpapers" "/usr/share/backgrounds"
copyDirContent "Scripts" "/home/$user/Scripts"
copyDirContent "X11/xorg.conf.d" "/etc/X11/xorg.conf.d"
copyDirContent "config" "/home/$user/.config"

copyHome ".face"
copyHome ".bashrc"
copyHome ".zshrc"
copyHome ".gtkrc-2.0"
copyHome ".xprofile"

unpackFiles "themes/GTK" "/usr/share/themes"
unpackFiles "themes/Icons" "/usr/share/icons"


# INSTALL LIGHTDM
printf "\n${BOLD}-- INSTALLING DISPLAY MANAGER --${RESET}\n"
installPackageArray "lightdm" "lightdm" "P"
installPackageArray "web-greeter lightdm-theme-neon-git" "lightdm" "A"
copyDirContent "lightdm" "/etc/lightdm/"
systemctl enable lightdm >>/dev/null 2>&1


# INSTALL PIPEWIRE
printf "\n${BOLD}-- INSTALLING PIPEWIRE --${RESET}\n"
printf "Removing potential conflicts (pulseaudio).\n"
pacman -Rdd --noconfirm pulseaudio-alsa pulseaudio-bluetooth pulseaudio jack2 >>/dev/null 2>&1
installPackageArray "pipewire wireplumber pipewire-alsa pipewire-pulse pipewire-jack" "audio" "P"

printf "Enabling pipewire services.\n"
sudo -u $user systemctl --global enable pipewire.socket >>/dev/null 2>&1 || printf "${RED}${BOLD}audio:${RESET}${RED} Failed to enable pipewire${RESET}\n" | tee -a "$ERRFILE"
sudo -u $user systemctl --global enable pipewire-pulse.socket >>/dev/null 2>&1 || printf "${RED}${BOLD}audio:${RESET}${RED} Failed to enable pipewire-pulse${RESET}\n" | tee -a "$ERRFILE"
sudo -u $user systemctl --global enable wireplumber.service >>/dev/null 2>&1 || printf "${RED}${BOLD}audio:${RESET}${RED} Failed to enable wireplumber${RESET}\n" | tee -a "$ERRFILE"


# Install packages from $PKGS
printf "\n${BOLD}-- INSTALLING PACKAGES --${RESET}\n"
installPackages


printf "\n${BOLD}-- FINISHING --${RESET}\n"
# Allow users to sudo with password and run some commands without password

echo "%wheel ALL=(ALL:ALL) ALL" >/etc/sudoers.d/00-wheel-can-sudo
echo "%wheel ALL=(ALL:ALL) NOPASSWD: /usr/bin/shutdown,/usr/bin/reboot,/usr/bin/systemctl suspend,/usr/bin/wifi-menu,/usr/bin/mount,/usr/bin/umount,/usr/bin/pacman -Syu,/usr/bin/pacman -Syyu,/usr/bin/pacman -Syyu --noconfirm,/usr/bin/loadkeys,/usr/bin/pacman -Syyuw --noconfirm,/usr/bin/pacman -S -u -y --config /etc/pacman.conf --,/usr/bin/pacman -S -y -u --config /etc/pacman.conf --" >/etc/sudoers.d/01-cmds-without-password


printf "\n"
printf "${BOLD}===========================${RESET}\n"
printf "${BOLD}== INSTALLATION FINISHED ==${RESET}\n"
printf "${BOLD}==     PLEASE REBOOT     ==${RESET}\n"
printf "${BOLD}===========================${RESET}\n"
