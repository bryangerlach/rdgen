from django import forms
from PIL import Image
import base64, json, uuid

class GenerateForm(forms.Form):
    # ---------------------------------------------------------------------
    # 1️⃣  Fields that map *directly* to the GitHub workflow inputs
    # ---------------------------------------------------------------------
    # Required by the workflow
    appname    = forms.CharField(label="Custom App Name", required=True)
    filename   = forms.CharField(label="DMG/EXE filename (without extension)", required=True)
    # The JSON object that contains version, company name, slogan, etc.
    # We'll collect the individual pieces below and build this JSON in the view.
    version    = forms.ChoiceField(
        choices=[
            ('master','nightly'),('1.4.9','1.4.9'),('1.4.8','1.4.8'),('1.4.7','1.4.7'),
            ('1.4.6','1.4.6'),('1.4.5','1.4.5'),('1.4.4','1.4.4'),('1.4.3','1.4.3'),
            ('1.4.2','1.4.2'),('1.4.1','1.4.1'),('1.4.0','1.4.0'),('1.3.9','1.3.9'),
            ('1.3.8','1.3.8'),('1.3.7','1.3.7'),('1.3.6','1.3.6'),('1.3.5','1.3.5'),
            ('1.3.4','1.3.4'),('1.3.3','1.3.3'),('1.3.2','1.3.2'),('1.3.1','1.3.1'),
            ('1.3.0','1.3.0')
        ],
        initial='1.4.9',
        label="RustDesk version to build"
    )
    # Optional but highly recommended fields
    compname   = forms.CharField(label="Company name (displayed in About dialog)", required=False)
    slogan     = forms.CharField(label="Slogan / quote (will be embedded via custom.txt)", required=False)
    # custom.txt content – free‑form text that ends up in the binary
    custom     = forms.CharField(widget=forms.Textarea, label="Custom txt content (will be base64‑encoded)", required=False)
    # Server configuration fields (passed straight through to the build)
    server     = forms.CharField(label="Rendezvous server", required=False)
    key        = forms.CharField(label="Public key (base64)", required=False)
    apiServer  = forms.CharField(label="API server", required=False)
    # ---------------------------------------------------------------------
    # 2️⃣  Optional UI‑only helpers – we will translate them to the JSON payload
    # ---------------------------------------------------------------------
    # Icon / logo – the UI lets the user upload a PNG; we convert it to a base64
    # string that the workflow expects inside `iconlink` / `logolink`.
    iconfile   = forms.FileField(label="Custom App Icon (PNG)", required=False, widget=forms.FileInput(attrs={'accept':'image/png'}))
    logofile   = forms.FileField(label="Custom App Logo (PNG)", required=False, widget=forms.FileInput(attrs={'accept':'image/png'}))
    # ---------------------------------------------------------------------
    # 3️⃣  Miscellaneous fields kept for backward compatibility (not used by the new workflow)
    # ---------------------------------------------------------------------
    sh_secret_field = forms.CharField(required=False)
    platform = forms.ChoiceField(
        choices=[('windows','Windows 64Bit'),('windows-x86','Windows 32Bit'),('linux','Linux'),('android','Android'),('macos','macOS')],
        initial='windows'
    )
    delayFix = forms.BooleanField(initial=True, required=False)
    exename = forms.CharField(label="Name for EXE file", required=False)
    direction = forms.ChoiceField(widget=forms.RadioSelect, choices=[('incoming','Incoming Only'),('outgoing','Outgoing Only'),('both','Bidirectional')], initial='both', required=False)
    installation = forms.ChoiceField(label="Disable Installation", choices=[('installationY','No, enable installation'),('installationN','Yes, DISABLE installation')], initial='installationY', required=False)
    settings = forms.ChoiceField(label="Disable Settings", choices=[('settingsY','No, enable settings'),('settingsN','Yes, DISABLE settings')], initial='settingsY', required=False)
    androidappid = forms.CharField(label="Custom Android App ID (replaces 'com.carriez.flutter_hbb')", required=False)
    serverIP = forms.CharField(label="Host", required=False)
    urlLink = forms.CharField(label="Custom URL for links", required=False)
    downloadLink = forms.CharField(label="Custom URL for downloading new versions", required=False)
    privacyfile = forms.FileField(label="Custom privacy screen (PNG)", required=False, widget=forms.FileInput(attrs={'accept':'image/png'}))
    iconbase64 = forms.CharField(required=False)
    logobase64 = forms.CharField(required=False)
    privacybase64 = forms.CharField(required=False)
    theme = forms.ChoiceField(choices=[('light','Light'),('dark','Dark'),('system','Follow System')], initial='system', required=False)
    themeDorO = forms.ChoiceField(choices=[('default','Default'),('override','Override')], initial='default')
    # Security / permissions – kept untouched for legacy UI
    passApproveMode = forms.ChoiceField(choices=[('password','Accept sessions via password'),('click','Accept sessions via click'),('password-click','Accepts sessions via both')],initial='password-click', required=False)
    permanentPassword = forms.CharField(widget=forms.PasswordInput(), required=False)
    denyLan = forms.BooleanField(initial=False, required=False)
    enableDirectIP = forms.BooleanField(initial=False, required=False)
    autoClose = forms.BooleanField(initial=False, required=False)
    permissionsDorO = forms.ChoiceField(choices=[('default','Default'),('override','Override')], initial='default')
    permissionsType = forms.ChoiceField(choices=[('custom','Custom'),('full','Full Access'),('view','Screen share')], initial='custom')
    enableKeyboard =  forms.BooleanField(initial=True, required=False)
    enableClipboard = forms.BooleanField(initial=True, required=False)
    enableFileTransfer = forms.BooleanField(initial=True, required=False)
    enableAudio = forms.BooleanField(initial=True, required=False)
    enableTCP = forms.BooleanField(initial=True, required=False)
    enableRemoteRestart = forms.BooleanField(initial=True, required=False)
    enableRecording = forms.BooleanField(initial=True, required=False)
    enableBlockingInput = forms.BooleanField(initial=True, required=False)
    enableRemoteModi = forms.BooleanField(initial=False, required=False)
    hidecm = forms.BooleanField(initial=False, required=False)
    enablePrinter = forms.BooleanField(initial=True, required=False)
    enableCamera = forms.BooleanField(initial=True, required=False)
    enableTerminal = forms.BooleanField(initial=True, required=False)
    removeWallpaper = forms.BooleanField(initial=True, required=False)
    defaultManual = forms.CharField(widget=forms.Textarea, required=False)
    overrideManual = forms.CharField(widget=forms.Textarea, required=False)
    cycleMonitor = forms.BooleanField(initial=False, required=False)
    xOffline = forms.BooleanField(initial=False, required=False)
    statussort = forms.BooleanField(initial=False, required=False)
    removeNewVersionNotif = forms.BooleanField(initial=False, required=False)

    # ---------------------------------------------------------------------
    # 4️⃣  Helper methods – validation & payload construction
    # ---------------------------------------------------------------------
    def clean_iconfile(self):
        image = self.cleaned_data.get('iconfile')
        if image:
            try:
                img = Image.open(image)
                if img.format != 'PNG':
                    raise forms.ValidationError("Only PNG images are allowed.")
                width, height = img.size
                if width != height:
                    raise forms.ValidationError("Custom App Icon dimensions must be square.")
                return image
            except OSError:
                raise forms.ValidationError("Invalid icon file.")
            except Exception as e:
                raise forms.ValidationError(f"Error processing icon: {e}")
        return image

    def clean_logofile(self):
        image = self.cleaned_data.get('logofile')
        if image:
            try:
                img = Image.open(image)
                if img.format != 'PNG':
                    raise forms.ValidationError("Only PNG images are allowed for the logo.")
                return image
            except OSError:
                raise forms.ValidationError("Invalid logo file.")
        return image

    def _file_to_base64(self, uploaded_file):
        """Utility – read an uploaded InMemoryUploadedFile and return a base64 string."""
        if not uploaded_file:
            return None
        # Ensure we read from the beginning
        uploaded_file.seek(0)
        data = uploaded_file.read()
        return base64.b64encode(data).decode()

    def build_payload(self):
        """Construct the dictionary that the view will JSON‑serialize
        and POST to the GitHub workflow.
        Returns a dict matching the schema expected by `trigger_build`.
        """
        # 1️⃣ Core required fields
        payload = {
            "appname": self.cleaned_data.get('appname'),
            "filename": self.cleaned_data.get('filename'),
            "extras": {
                "version": self.cleaned_data.get('version'),
                "compname": self.cleaned_data.get('compname') or "",
                "slogan": self.cleaned_data.get('slogan') or "",
                # Flags that map to the extra‑feature checkboxes – only include if true
                "rdgen": self.cleaned_data.get('rdgen') if hasattr(self, 'rdgen') else False,
                "delayFix": "true" if self.cleaned_data.get('delayFix') else "false",
                "cycleMonitor": "true" if self.cleaned_data.get('cycleMonitor') else "false",
                "xOffline": "true" if self.cleaned_data.get('xOffline') else "false",
                "statussort": "true" if self.cleaned_data.get('statussort') else "false",
                "removeNewVersionNotif": "true" if self.cleaned_data.get('removeNewVersionNotif') else "false",
                # add any other boolean fields you care about here …
            },
            "custom": base64.b64encode((self.cleaned_data.get('custom') or "").encode()).decode(),
            "uuid": str(uuid.uuid4()),
            "server": self.cleaned_data.get('server') or "",
            "key": self.cleaned_data.get('key') or "",
            "apiServer": self.cleaned_data.get('apiServer') or "",
        }

        # 2️⃣ Optional icon / logo handling – convert to the structure the workflow expects
        icon_b64 = self._file_to_base64(self.cleaned_data.get('iconfile'))
        if icon_b64:
            payload['iconlink'] = json.dumps({
                "url": "https://your-icon-service.example.com",
                "file": self.cleaned_data.get('iconfile').name,
                "uuid": payload['uuid']
            })
        else:
            payload['iconlink'] = 'false'

        logo_b64 = self._file_to_base64(self.cleaned_data.get('logofile'))
        if logo_b64:
            payload['logolink'] = json.dumps({
                "url": "https://your-logo-service.example.com",
                "file": self.cleaned_data.get('logofile').name,
                "uuid": payload['uuid']
            })
        else:
            payload['logolink'] = 'false'

        # 3️⃣ Ensure any empty strings are turned into the literal "false" that the workflow expects
        for k in ['server', 'key', 'apiServer']:
            if not payload[k]:
                payload[k] = ''

        return payload

    sh_secret_field = forms.CharField(required=False)
    #Platform
    platform = forms.ChoiceField(choices=[('windows','Windows 64Bit'),('windows-x86','Windows 32Bit'),('linux','Linux'),('android','Android'),('macos','macOS')], initial='windows')
    version = forms.ChoiceField(choices=[('master','nightly'),('1.4.9','1.4.9'),('1.4.8','1.4.8'),('1.4.7','1.4.7'),('1.4.6','1.4.6'),('1.4.5','1.4.5'),('1.4.4','1.4.4'),('1.4.3','1.4.3'),('1.4.2','1.4.2'),('1.4.1','1.4.1'),('1.4.0','1.4.0'),('1.3.9','1.3.9'),('1.3.8','1.3.8'),('1.3.7','1.3.7'),('1.3.6','1.3.6'),('1.3.5','1.3.5'),('1.3.4','1.3.4'),('1.3.3','1.3.3'),('1.3.2','1.3.2'),('1.3.1','1.3.1'),('1.3.0','1.3.0')], initial='1.4.9')
    delayFix = forms.BooleanField(initial=True, required=False)

    #General
    exename = forms.CharField(label="Name for EXE file", required=False)
    appname = forms.CharField(label="Custom App Name", required=False)
    direction = forms.ChoiceField(widget=forms.RadioSelect, choices=[
        ('incoming', 'Incoming Only'),
        ('outgoing', 'Outgoing Only'),
        ('both', 'Bidirectional')
    ], initial='both', required=False)
    installation = forms.ChoiceField(label="Disable Installation", choices=[
        ('installationY','No, enable installation'),
        ('installationN','Yes, DISABLE installation')
    ], initial='installationY', required=False)
    settings = forms.ChoiceField(label="Disable Settings", choices=[
        ('settingsY', 'No, enable settings'),
        ('settingsN', 'Yes, DISABLE settings')
    ], initial='settingsY', required=False)
    androidappid = forms.CharField(label="Custom Android App ID (replaces 'com.carriez.flutter_hbb')", required=False)

    #Custom Server
    serverIP = forms.CharField(label="Host", required=False)
    apiServer = forms.CharField(label="API Server", required=False)
    key = forms.CharField(label="Key", required=False)
    urlLink = forms.CharField(label="Custom URL for links", required=False)
    downloadLink = forms.CharField(label="Custom URL for downloading new versions", required=False)
    compname = forms.CharField(label="Company name",required=False)

    #Visual
    iconfile = forms.FileField(label="Custom App Icon (in .png format)", required=False, widget=forms.FileInput(attrs={'accept': 'image/png'}))
    logofile = forms.FileField(label="Custom App Logo (in .png format)", required=False, widget=forms.FileInput(attrs={'accept': 'image/png'}))
    privacyfile = forms.FileField(label="Custom privacy screen (in .png format)", required=False, widget=forms.FileInput(attrs={'accept': 'image/png'}))
    iconbase64 = forms.CharField(required=False)
    logobase64 = forms.CharField(required=False)
    privacybase64 = forms.CharField(required=False)
    theme = forms.ChoiceField(choices=[
        ('light', 'Light'),
        ('dark', 'Dark'),
        ('system', 'Follow System')
    ], initial='system', required=False)
    themeDorO = forms.ChoiceField(choices=[('default', 'Default'),('override', 'Override')], initial='default', required=False)

    #Security
    passApproveMode = forms.ChoiceField(choices=[('password','Accept sessions via password'),('click','Accept sessions via click'),('password-click','Accepts sessions via both')],initial='password-click', required=False)
    permanentPassword = forms.CharField(widget=forms.PasswordInput(), required=False)
    #runasadmin = forms.ChoiceField(choices=[('false','No'),('true','Yes')], initial='false')
    denyLan = forms.BooleanField(initial=False, required=False)
    enableDirectIP = forms.BooleanField(initial=False, required=False)
    #ipWhitelist = forms.BooleanField(initial=False, required=False)
    autoClose = forms.BooleanField(initial=False, required=False)

    #Permissions
    permissionsDorO = forms.ChoiceField(choices=[('default', 'Default'),('override', 'Override')], initial='default', required=False)
    permissionsType = forms.ChoiceField(choices=[('custom', 'Custom'),('full', 'Full Access'),('view','Screen share')], initial='custom', required=False)
    enableKeyboard =  forms.BooleanField(initial=True, required=False)
    enableClipboard = forms.BooleanField(initial=True, required=False)
    enableFileTransfer = forms.BooleanField(initial=True, required=False)
    enableAudio = forms.BooleanField(initial=True, required=False)
    enableTCP = forms.BooleanField(initial=True, required=False)
    enableRemoteRestart = forms.BooleanField(initial=True, required=False)
    enableRecording = forms.BooleanField(initial=True, required=False)
    enableBlockingInput = forms.BooleanField(initial=True, required=False)
    enableRemoteModi = forms.BooleanField(initial=False, required=False)
    hidecm = forms.BooleanField(initial=False, required=False)
    enablePrinter = forms.BooleanField(initial=True, required=False)
    enableCamera = forms.BooleanField(initial=True, required=False)
    enableTerminal = forms.BooleanField(initial=True, required=False)

    #Other
    removeWallpaper = forms.BooleanField(initial=True, required=False)

    defaultManual = forms.CharField(widget=forms.Textarea, required=False)
    overrideManual = forms.CharField(widget=forms.Textarea, required=False)

    #custom added features
    cycleMonitor = forms.BooleanField(initial=False, required=False)
    xOffline = forms.BooleanField(initial=False, required=False)
    statussort = forms.BooleanField(initial=False, required=False)
    removeNewVersionNotif = forms.BooleanField(initial=False, required=False)

    def clean_iconfile(self):
        image = self.cleaned_data.get('iconfile')
        if image:
            try:
                img = Image.open(image)
                if img.format != 'PNG':
                    raise forms.ValidationError("Only PNG images are allowed.")
                width, height = img.size
                if width != height:
                    raise forms.ValidationError("Custom App Icon dimensions must be square.")
                return image
            except OSError:
                raise forms.ValidationError("Invalid icon file.")
            except Exception as e:
                raise forms.ValidationError(f"Error processing icon: {e}")
        return image