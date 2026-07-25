from django import forms
from PIL import Image

class GenerateForm(forms.Form):
    sh_secret_field = forms.CharField(required=False)
    #Platform
    platform = forms.ChoiceField(choices=[('windows','Windows'),('linux','Linux'),('android','Android'),('macos','macOS'),('all','全平台构建')], initial='windows')
    version = forms.ChoiceField(choices=[('master','nightly'),('1.4.9','1.4.9'),('1.4.8','1.4.8'),('1.4.7','1.4.7'),('1.4.6','1.4.6'),('1.4.5','1.4.5'),('1.4.4','1.4.4'),('1.4.3','1.4.3'),('1.4.2','1.4.2'),('1.4.1','1.4.1'),('1.4.0','1.4.0')], initial='1.4.9')
    help_text="'master' 是开发版本（每日构建），拥有最新功能，但可能不太稳定"
    delayFix = forms.BooleanField(initial=True, required=False)

    #General
    exename = forms.CharField(label="EXE 文件名称", required=True)
    appname = forms.CharField(label="自定义应用名称", required=False)
    direction = forms.ChoiceField(widget=forms.RadioSelect, choices=[
        ('incoming', '仅接受传入'),
        ('outgoing', '仅传出'),
        ('both', '双向')
    ], initial='both')
    installation = forms.ChoiceField(label="禁用安装", choices=[
        ('installationY', '否，启用安装'),
        ('installationN', '是，禁用安装')
    ], initial='installationY')
    settings = forms.ChoiceField(label="禁用设置", choices=[
        ('settingsY', '否，启用设置'),
        ('settingsN', '是，禁用设置')
    ], initial='settingsY')
    androidappid = forms.CharField(label="自定义 Android 应用 ID（替换 'com.carriez.flutter_hbb'）", required=False)

    #Custom Server
    serverIP = forms.CharField(label="主机", required=False)
    apiServer = forms.CharField(label="API 服务器", required=False)
    key = forms.CharField(label="密钥", required=False)
    urlLink = forms.CharField(label="自定义链接 URL", required=False)
    downloadLink = forms.CharField(label="自定义更新下载 URL", required=False)
    compname = forms.CharField(label="公司名称",required=False)

    #Visual
    iconfile = forms.FileField(label="自定义应用图标（.png 格式）", required=False, widget=forms.FileInput(attrs={'accept': 'image/png'}))
    logofile = forms.FileField(label="自定义应用 Logo（.png 格式）", required=False, widget=forms.FileInput(attrs={'accept': 'image/png'}))
    privacyfile = forms.FileField(label="自定义隐私屏幕（.png 格式）", required=False, widget=forms.FileInput(attrs={'accept': 'image/png'}))
    iconbase64 = forms.CharField(required=False)
    logobase64 = forms.CharField(required=False)
    privacybase64 = forms.CharField(required=False)
    theme = forms.ChoiceField(choices=[
        ('light', '浅色'),
        ('dark', '深色'),
        ('system', '跟随系统')
    ], initial='system')
    themeDorO = forms.ChoiceField(choices=[('default', '默认'),('override', '覆盖')], initial='default')

    #Security
    passApproveMode = forms.ChoiceField(choices=[('password','通过密码接受会话'),('click','通过点击接受会话'),('password-click','通过两种方式接受会话')],initial='password-click')
    permanentPassword = forms.CharField(widget=forms.PasswordInput(), required=False)
    #runasadmin = forms.ChoiceField(choices=[('false','No'),('true','Yes')], initial='false')
    denyLan = forms.BooleanField(initial=False, required=False)
    enableDirectIP = forms.BooleanField(initial=False, required=False)
    #ipWhitelist = forms.BooleanField(initial=False, required=False)
    autoClose = forms.BooleanField(initial=False, required=False)

    #Permissions
    permissionsDorO = forms.ChoiceField(choices=[('default', '默认'),('override', '覆盖')], initial='default')
    permissionsType = forms.ChoiceField(choices=[('custom', '自定义'),('full', '完全访问'),('view','屏幕共享')], initial='custom')
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
    xOffline = forms.BooleanField(initial=False, required=False)
    removeNewVersionNotif = forms.BooleanField(initial=False, required=False)

    def clean_iconfile(self):
        print("checking icon")
        image = self.cleaned_data['iconfile']
        if image:
            try:
                # Open the image using Pillow
                img = Image.open(image)

                # Check if the image is a PNG (optional, but good practice)
                if img.format != 'PNG':
                    raise forms.ValidationError("只允许 PNG 格式的图片。")

                # Get image dimensions
                width, height = img.size

                # Check for square dimensions
                if width != height:
                    raise forms.ValidationError("自定义应用图标的尺寸必须为正方形。")
                
                return image
            except OSError:  # Handle cases where the uploaded file is not a valid image
                raise forms.ValidationError("无效的图标文件。")
            except Exception as e: # Catch any other image processing errors
                raise forms.ValidationError(f"处理图标时出错：{e}")
