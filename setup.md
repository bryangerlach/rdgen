## To fully host the client generator yourself, you will need to following:

<ol>
    <li>A Github account with a fork of this repo  </li>
    <li>A Github fine-grained access token with permissions for your rdgen repository  
        <ul>
            <li>login to your github account  </li>
            <li>click on your profile picture at the top right, click Settings  </li>
            <li>at the bottom of the left panel, click Developer Settings  </li>
            <li>click Personal access tokens  </li>
            <li>click Fine-grained tokens  </li>
            <li>click Generate new token  </li>
            <li>give a token name, change expiration to whatever you want  </li>
            <li>under Repository acces, select Only select repositories, then pick your rdgen repo  </li>
            <li>give Read and Write access to actions and workflows  </li>
        </ul>
    </li>
    <li>Setup environment variables / secrets:
        <ul>
            <li>environment variables on the server running rdgen:  
                <ul>
                <li>GHUSER="your github username"  </li>
                <li>GHBEARER="your fine-graned access token"  </li>
                </ul></li>
            <li>github secrets (setup on your github account for your rdgen repo):  
                <oul>
                <li>GENURL="example.com:8000"  </li>
                *this is the domain and port that your are running rdgen on, needs to be accesible on the internet
                </ul></li>
            <li>optional github secrets (for signing the code):  
                <ul>
                <li>WINDOWS_PFX_BASE64  </li> 
                <li>WINDOWS_PFX_PASSWORD  </li> 
                <li>WINDOWS_PFX_SHA1_THUMBPRINT</li>  
                </ul></li> 
        </ul>
    </li>
</ol>

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

### use nginx, caddy, traefik, etc. for ssl reverse proxy
