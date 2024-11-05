## To fully host the client generator yourself, you will need to following:

### 1) A Github account with a fork of this repo  
### 2) A Github fine-grained access token with permissions for your rdgen repository  
    a) login to your github account  
    b) click on your profile picture at the top right, click Settings  
    c) at the bottom of the left panel, click Developer Settings  
    d) click Personal access tokens  
    e) click Fine-grained tokens  
    f) click Generate new token  
    g) give a token name, change expiration to whatever you want  
    h) under Repository acces, select Only select repositories, then pick your rdgen repo  
    i) give Read and Write access to actions and workflows  
### 3) On the server running the client generator:
    a) environment variables:  
        GHUSER="your github username"  
        GHBEARER="your fine-graned access token"  
    b) github secrets (setup on your github account for your rdgen repo):  
        GENURL="example.com:8083"               |  this is the domain and port that your are running rdgen on, needs to be accesible on the internet
    c) optional github secrets (for signing the code):  
        WINDOWS_PFX_BASE64  
        WINDOWS_PFX_PASSWORD  
        WINDOWS_PFX_SHA1_THUMBPRINT  

## To run rdgen on your server:  

### open to the directory you want to install rdgen (change /opt to wherever you want)  
> cd /opt

### clone your rdgen repo, change bryangerlach to your github username
> git clone https://github.com/bryangerlach/rdgen.git

### open the rdgen directory
> cd rdgen

### setup a python virtual environment called rdgen
> python -m venv rdgen

### activate the python virtual environment 
> source rdgen/bin/activate

### install the python dependencies
> pip install -r requirements.txt

### setup the database
> python manage.py migrate

### run the server, change 8000 with whatever you want
> python manage.py runserver 0.0.0.0:8000

### open your web browser to yourdomain:8000
