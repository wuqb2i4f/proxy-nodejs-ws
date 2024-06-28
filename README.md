# Project Setup and Management Script

This README explains how to set up and use the `start.sh` script to manage the project components.

## Initial Setup

1. Connect to your host using SSH:
```
ssh <username>@<panel>.serv00.com
```
Use the information emailed to you by serv00.

2. Enable management permissions:
```
devil binexec on
```
***AFTER THIS STEP, EXIT FROM SSH AND LOG IN AGAIN.***

3. Clone the repository:
```
cd domains/<username>.serv00.net
git clone https://github.com/wuqb2i4f/serv00-vless-ws.git
cd serv00-vless-ws
```

## Usage

To use the script, run:
```
./start.sh <option>
```

| Step | Command | Description |
|------|---------|-------------|
| 0. All-in-One | `./start.sh 0` | Executes all steps in a single command |
| 1. Initialize | `./start.sh 1` | Prepares environment for all components |
| 2. Run Cloudflared | `./start.sh 2` | Starts Cloudflared and generates configs |
| 3. Run Node.js server | `./start.sh 3` | Starts Node.js server with maintenance cron job |
| 4. Run Xray | `./start.sh 4` | Starts Xray with maintenance cron job |
| 5. Show VLESS links | `./start.sh 5` | Displays VLESS connection links from `node/.env` |

***NODE.JS AND XRAY CANNOT BE ACTIVE SIMULTANEOUSLY. ONLY ONE OF THEM SHOULD BE RUNNING AT A TIME.***

## Checking Sessions

To check the status of a specific component, you can attach to its tmux session:
```
tmux attach -t <session>
```
Replace `<session>` with:
- `cf` for Cloudflared
- `no` for Node.js
- `xr` for Xray

For example, to check the Cloudflared session:
```
tmux attach -t cf
```
To detach from a tmux session without closing it, press:
```
Ctrl + b, then d
```
This key combination allows you to exit the session while leaving it running in the background.

## Notes

- The script uses tmux to manage sessions for each component.
- Cron jobs are set up for periodic maintenance of Node.js and Xray.
- Cloudflared, Node.js, and Xray configurations are generated automatically.
- The script includes functions for port management and cleanup.
