## To fully host the client generator yourself, you will need to following:

1. A Github account with a fork of this repo  
2. A Github fine-grained access token with permissions for your rdgen
   repository:
    * login to your github account  
    * click on your profile picture at the top right, click Settings  
    * at the bottom of the left panel, click Developer Settings  
    * click Personal access tokens  
    * click Fine-grained tokens  
    * click Generate new token  
    * give a token name, change expiration to whatever you want  
    * under Repository access, select Only select repositories, then pick your
      rdgen repo  
    * give Read and Write access to actions and workflows  
    * You might have to go to: https://github.com/USERNAME/rdgen/actions and hit green Enable Actions button so it works.
3. Setup environment variables/secrets:
    * environment variables on the server running rdgen:  
        * GHUSER="your github username"  
        * GHBEARER="your fine-grained access token"  
        * PROTOCOL="https" *optional - defaults to "https", change to "http" if you need to
        * REPONAME="rdgen" *optional - defaults to "rdgen", change this if you renamed the repo when you forked it
    * github secrets (setup on your github account for your rdgen repo):  
        * GENURL="example.com:8000"  *this is the domain and port that you are
          running rdgen on, needs to be accessible on the internet, depending
          on how you have this setup the port may not be needed  
    * optional github secrets (for signing the code):  
        * WINDOWS_PFX_BASE64  
        * WINDOWS_PFX_PASSWORD  
        * WINDOWS_PFX_SHA1_THUMBPRINT  
    

## A few notes:

* If you change your repository name, make sure to change the url on lines
  172-203 of views.py to reflect the change
* If you are running on http instead of https, make sure to make the change on
  line 75 of views.py
  
## To run rdgen on your server without docker:  

```
# Open to the directory you want to install rdgen (change /opt to wherever you want)  
cd /opt

# Clone your rdgen repo, change bryangerlach to your github username
git clone https://github.com/bryangerlach/rdgen.git

# Open the rdgen directory
cd rdgen

# Setup a python virtual environment called rdgen
python -m venv .venv

# Activate the python virtual environment 
source .venv/bin/activate

# Install the python dependencies
pip install -r requirements.txt

# Setup the database
python manage.py migrate

# Run the server, change 8000 with whatever you want
python manage.py runserver 0.0.0.0:8000
```

open your web browser to yourdomain:8000

use nginx, caddy, traefik, etc. for ssl reverse proxy

## To autostart the server on boot, you can set up a systemd service called rdgen.service

replace user, group, and port if you need to  replace /opt with wherever you
have installed rdgen  save the following file as
/etc/systemd/system/rdgen.service, and make sure to change GHUSER, GHBEARER

```
[Unit]
Description=Rustdesk Client Generator
[Service]
Type=simple
LimitNOFILE=1000000
Environment="GHUSER=yourgithubusername"
Environment="GHBEARER=yourgithubtoken"
PassEnvironment=GHUSER GHBEARER
ExecStart=/opt/rdgen/.venv/bin/python3 /opt/rdgen/manage.py runserver 0.0.0.0:8000
WorkingDirectory=/opt/rdgen/
User=root
Group=root
Restart=always
StandardOutput=file:/var/log/rdgen.log
StandardError=file:/var/log/rdgen.error
# Restart service after 10 seconds if node service crashes
RestartSec=10
[Install]
WantedBy=multi-user.target
```

then run this to enable autostarting the service on boot, and then start it
manually this time:

```
sudo systemctl enable rdgen.service
sudo systemctl start rdgen.service
```
and to get the status of the server, run:
```
sudo systemctl status rdgen.service
```
