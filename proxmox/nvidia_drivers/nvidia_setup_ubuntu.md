# Clean setup for NVIDIA drivers on Ubuntu guests

Clean up previous installations, if needed. Use _purge_, not _remove_, to ensure clean up scripts are executed after removing the packages.
```bash
apt list --installed | grep nvidia # Check if NVIDIA drivers are already installed (if not, don't run the following command)
sudo apt purge 'nvidia-*' 'libnvidia-*' 'linux-objects-nvidia-*' # Purge all packages related to a specific version of the drivers
                                                                 # (e.g., ending with "580"). Surely, DO NOT PURGE kernel-related ones (e.g.,
                                                                 # "linux-firmware", "linux-signature")
```

Check that all the intended packages have actually been removed. Only linux-firmware (i.e., kernel-related) and linux-signature nvidia packages (secure-boot related, I guess) should remain.
```bash
apt list --installed | grep nvidia
```

Reboot the system for good measure.
```bash
sudo reboot
```

Upgrade system packages (this is a good chance to do it) and reboot to ensure booting on the latest kernel before proceeding.
```bash
sudo apt update
sudo apt upgrade

sudo reboot
```

Install NVIDIA drivers leveraging the official Ubuntu tool (_ubuntu-drivers_), which works egregiously.
```bash
ubuntu-drivers devices # Check if your NVIDIA GPU is detected and the recommended version of the driver
sudo ubuntu-drivers install # With no further options, it installs the recommended drivers for the detected GPU
```

Install container-related packages (e.g., needed for Docker or Podman to work correctly), which were likely purged at the beginning.
```bash
sudo apt install libnvidia-container1 libnvidia-container-tools nvidia-container-toolkit nvidia-container-toolkit-base
```

Produce (or update; the command is the same) the CDI manifest required by Podman to use the currently installed GPUs from within containers. Generally, this runs automatically when updating NVIDIA drivers, but sometimes it might not happen, especially when doing first or clean installations. Moreover, **if you change the GPU(s) passed through to the VM, you most likely need to update the CDI manifest as well**. Choose the command from those below based on your current podman version.
```bash
# Look up your podman version
podman --version
# Command to run if podman version >=5.1.0
sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml
# Command to run if podman version is <5.1.0. This alternative generates a CDI manifest that is still compatible with that version.
# Note: Podman is kept to 4.9.3 in Ubuntu 24.04 LTS. Upgrading to 26.01 LTS solves this issue.
sudo nvidia-ctk cdi generate --feature-flag no-additional-gids-for-device-nodes --output=/etc/cdi/nvidia.yaml
```

Reboot to ensure all modules are loaded correctly.
```bash
sudo reboot
```

Let's do some checks.
```bash
# To test the connection between NVIDIA drivers and the GPU works:
nvidia-smi
# To test podman access to the GPU with a lightweight container (this should return the same output as the previous command):
podman run --rm --device nvidia.com/gpu=all ubuntu nvidia-smi
# If you wish to remove the container image afterwards:
podman images
podman rmi <image_id>
```