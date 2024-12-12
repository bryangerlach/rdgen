from django import forms

class GenerateForm(forms.Form):
    #Platform
    platform = forms.ChoiceField(choices=[('windows','Windows'),('linux','Linux (currently unavailable)'),('android','Android (testing now available)')], initial='windows')
    version = forms.ChoiceField(choices=[('master','nightly'),('1.3.5','1.3.5'),('1.3.4','1.3.4'),('1.3.3','1.3.3'),('1.3.2','1.3.2'),('1.3.1','1.3.1'),('1.3.0','1.3.0')], initial='1.3.5')
    delayFix = forms.BooleanField(initial=True, required=False)

    #General
    exename = forms.CharField(label="Name for EXE file", required=True)
    appname = forms.CharField(label="Custom App Name", required=False)
    direction = forms.ChoiceField(widget=forms.RadioSelect, choices=[
        ('incoming', 'Incoming Only'),
        ('outgoing', 'Outgoing Only'),
        ('both', 'Bidirectional')
    ], initial='both')
    installation = forms.ChoiceField(label="Disable Installation", choices=[
        ('installationY', 'No, enable installation'),
        ('installationN', 'Yes, DISABLE installation')
    ], initial='installationY')
    settings = forms.ChoiceField(label="Disable Settings", choices=[
        ('settingsY', 'No, enable settings'),
        ('settingsN', 'Yes, DISABLE settings')
    ], initial='settingsY')

    #Custom Server
    serverIP = forms.CharField(label="Host", required=False)
    apiServer = forms.CharField(label="API Server", required=False)
    key = forms.CharField(label="Key", required=False)
    urlLink = forms.CharField(label="Custom URL for links", required=False)

    #Visual
    iconfile = forms.FileField(label="Custom App Icon (in .png format)", required=False, widget=forms.FileInput(attrs={'accept': 'image/png'}))
    logofile = forms.FileField(label="Custom App Logo (in .png format)", required=False, widget=forms.FileInput(attrs={'accept': 'image/png'}))
    theme = forms.ChoiceField(choices=[
        ('light', 'Light'),
        ('dark', 'Dark'),
        ('system', 'Follow System')
    ], initial='system')
    themeDorO = forms.ChoiceField(choices=[('default', 'Default'),('override', 'Override')], initial='default')

    #Security
    passApproveMode = forms.ChoiceField(choices=[('password','Accept sessions via password'),('click','Accept sessions via click'),('password-click','Accepts sessions via both')],initial='password-click')
    permanentPassword = forms.CharField(widget=forms.PasswordInput(), required=False)
    runasadmin = forms.ChoiceField(choices=[('false','No'),('true','Yes')], initial='false')
    denyLan = forms.BooleanField(initial=False, required=False)
    enableDirectIP = forms.BooleanField(initial=False, required=False)
    #ipWhitelist = forms.BooleanField(initial=False, required=False)
    autoClose = forms.BooleanField(initial=False, required=False)

    #Permissions
    permissionsDorO = forms.ChoiceField(choices=[('default', 'Default'),('override', 'Override')], initial='default')
    permissionsType = forms.ChoiceField(choices=[('custom', 'Custom'),('full', 'Full Access'),('view','Screen share')], initial='custom')
    enableKeyboard =  forms.BooleanField(initial=True, required=False)
    enableClipboard = forms.BooleanField(initial=True, required=False)
    enableFileTransfer = forms.BooleanField(initial=True, required=False)
    enableAudio = forms.BooleanField(initial=True, required=False)
    enableTCP = forms.BooleanField(initial=True, required=False)
    enableRemoteRestart = forms.BooleanField(initial=True, required=False)
    enableRecording = forms.BooleanField(initial=True, required=False)
    enableBlockingInput = forms.BooleanField(initial=True, required=False)
    enableRemoteModi = forms.BooleanField(initial=False, required=False)

    #Other
    removeWallpaper = forms.BooleanField(initial=True, required=False)

    defaultManual = forms.CharField(widget=forms.Textarea, required=False)
    overrideManual = forms.CharField(widget=forms.Textarea, required=False)

    #custom added features
    cycleMonitor = forms.BooleanField(initial=False, required=False)
    xOffline = forms.BooleanField(initial=False, required=False)