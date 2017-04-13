# Algo VPN Driver Script

Some driver scripts for [Algo][algo-gh]. Although Algo's installation process is
already very easy to use, I wanted something that didn't require user
interaction.

## Features

- Installs Algo's dependencies.
- Installs other useful tools, such as `htop`.
- Finds parameters to pass into Algo, such as the IP address.

## Usage

1. Paste the entire script into your provider's cloud-init box when creating
   your VPS.
2. If you want to use the SSH tunnel, make sure the provider will write keys to
   `/root/.ssh/authorized_keys`.
3. Log into the server and wait for a .mobileconfig file to appear in
   `/root/algo/configs/`.

If you're just experimenting, you can launch a free DigitalOcean instance for 2
hours using [dply.co](https://dply.co/).

[algo-gh]: https://github.com/trailofbits/algo
