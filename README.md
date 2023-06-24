# Autoinstall Script
---

Automatically sets up home directory for a new user and installs packages specified in package lists.

## Packages
Current package lists:

| List     | Summary | Included by default |
|----------|---------|---------------------|
| xorg     | Xorg stuff, my dwm fork, polybar and picom                                        | no  |
| wayland  | Hyprland, waybar                                                                  | no  |
| fonts    | Fonts used in my configs                                                          | yes |
| base     | Basic stuff (e.g. terminal emulator, vim, neovim, ...)                            | yes |
| standard | Nice to have, but not necessary (e.g. file manager, firefox, ...)| no  |
| extra    | My personal preferences (obs, lazygit, minecraft launcher, spotify, ...)          | no  |
| laptop   | Laptop specific (tlp, screen rotation, ...)                                       | no  |

## Usage
```
Usage:
	./autoinstall.sh --user=<username> (--wayland | --xorg) [--symlink] [--packages=<package-list>]

Options:
	-u | --user             username
	-w | --wayland          install wayland packages (hyprland + waybar)
	-x | --xorg             install xorg packages (dwm + polybar)
	-l | --link             symlink config files instead of copying
                                (useful for syncing changes with repo)
	-s | --swaylock         use swaylock instead of lightdm
                                (both will be installed anyway)
	-p | --packages         extra packages to install (standard, extra)

Example: 
	./autoinstall.sh --user=desktop31 --wayland --xorg --packages=standard,extra,laptop
```

When the `--swaylock` option is used, lightdm.service and dmlock.service won't be enabled, but lightdm
will be installed anyway. 

If you're using my dotfiles, you will have to uncomment the line `exec-once = ~/.config/hypr/swayidle`
in `~/.config/hypr/autostart.conf` for swaylock to work on suspend.

If you're installing this on a laptop, you might want to switch to laptop waybar configuration in <br>
`~/.config/waybar/config` by uncommenting the modules for laptop and commenting out desktop modules.

## Running the script
You must run the script as the root user. <br>
Please update your system before running the script.

It is recommended to run this ONLY on a base arch installation. <br>
If you already have a full system and a user setup, it *should* also work, but some stuff might be overriden (not tested, feel free to break your system :trollface:)

**NOTE:** You might want to review at least the *EXECUTION* section of the script (at the bottom) to learn what it is actually doing

// TODO: Add a video
