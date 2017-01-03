{CompositeDisposable} = require 'atom'
{dirname, join} = require 'path'
clipboard = require 'clipboard'
fs = require 'fs'


module.exports =
    subscriptions : null

    activate : ->
        @subscriptions = new CompositeDisposable
        @subscriptions.add atom.commands.add 'atom-workspace',
            'markdown-img-paste:paste' : => @paste()

    deactivate : ->
        @subscriptions.dispose()

    paste : ->
        if !cursor = atom.workspace.getActiveTextEditor() then return
        #只在markdown中使用
        if atom.config.get 'markdown-img-paste.only_markdown'
            if !grammar = cursor.getGrammar() then return

            if cursor.getPath()
                if  cursor.getPath().substr(-3) != '.md' and
                    cursor.getPath().substr(-9) != '.markdown' and
                    grammar.scopeName != 'source.gfm'
                        return
            else
                if grammar.scopeName != 'source.gfm' then return

        img = clipboard.readImage()
        if img.isEmpty() then return

        #filename = "markdown-img-paste-#{new Date().format()}.png"
        filename = "#{new Date().format()}.png"
        foldername = cursor.getFileName().slice(0, -3)
        #fullname = join(dirname(cursor.getPath()), 'asset', filename)
        #fullname = join(dirname(path.dirname(cursor.getPath())),'img', filename)
        fullname = join(dirname(dirname(cursor.getPath())), 'img',foldername, filename)



        if !fs.existsSync  dirname(fullname)
            fs.mkdirSync  dirname(fullname)

        fs.writeFileSync fullname, img.toPng()



        #上传至sm.ms
        if atom.config.get 'markdown-img-paste.upload_to_mssm'
            request = require 'request'
            formData = {
              smfile: fs.createReadStream fullname,
              ssl: 1
            }


            options =
                uri: 'https://sm.ms/api/upload'
                formData: formData


            request.post options, (err, response, body) ->
                if err
                    atom.notifications.addError 'Upload failed:' + err
                else
                    body = JSON.parse body
                    if body.code == 'error'
                        atom.notifications.addError 'Upload failed:' + body.msg
                    else
                        atom.notifications.addSuccess 'OK, image upload to sm.ms!'
                        #mdtext = '![](' + body.data.url + ')'
                        mdtext = '!['+foldername+'/'+filename+'](https://ooo.0o0.ooo' + body.data.path + ')'
                        paste_mdtext cursor, mdtext

            #delete_file(fullname)

            #完成
            return


        #保存在本地
        if !atom.config.get('markdown-img-paste.upload_to_qiniu')
            mdtext = '![](' + fullname + ')'
            #mdtext = '![](../img/' + filename + ')' # 原本是 '![](' + fullname + ')'，修改成 '![](../images/' + filename + ')'

            paste_mdtext cursor, mdtext

        #使用七牛存储图片
        else
            qiniu = require 'qiniu'

            qiniu.conf.ACCESS_KEY = atom.config.get 'markdown-img-paste.zAccessKey'
            qiniu.conf.SECRET_KEY = atom.config.get 'markdown-img-paste.zSecretKey'

            #要上传的空间
            bucket = atom.config.get 'markdown-img-paste.zbucket'

            #七牛空间域名
            domain = atom.config.get 'markdown-img-paste.zdomain'

            #上传到七牛后保存的文件名
            key = filename

            #构建上传策略函数
            uptoken = (bucket, key) ->
                putPolicy = new qiniu.rs.PutPolicy(bucket+":"+key)
                putPolicy.token()

            #生成上传 Token
            token = uptoken bucket, key

            #要上传文件的本地路径
            filePath = fullname

            #构造上传函数
            uploadFile = (uptoken, key, localFile) ->
                extra = new qiniu.io.PutExtra()
                qiniu.io.putFile uptoken, key, localFile, extra, (err, ret) ->
                    if !err
                        #上传成功， 处理返回值
                        #console.log(ret.hash, ret.key, ret.persistentId);
                        atom.notifications.addSuccess 'OK, image upload to qiniu!'

                        pastepath =  domain + '/' +  filename
                        mdtext = '![](' + pastepath + ')'
                        paste_mdtext cursor, mdtext
                    else
                        #上传失败， 处理返回代码
                        atom.notifications.addError 'Upload Failed:' + err

            #调用uploadFile上传
            uploadFile token, key, filePath

            delete_file fullname

#辅助函数
delete_file = (file_path) ->
    fs.unlink file_path, (err) ->
        if err
            console.log '未删除本地文件:'+ fullname

paste_mdtext = (cursor, mdtext) ->
    cursor.insertText mdtext
    position = cursor.getCursorBufferPosition()
    position.column = position.column - mdtext.length + 2
    cursor.setCursorBufferPosition position


Date.prototype.format = ->

    shift2digits = (val) ->
        if val < 10
            return "0#{val}"
        return val

    year = @getFullYear()
    month = shift2digits @getMonth()+1
    day = shift2digits @getDate()
    hour = shift2digits @getHours()
    minute = shift2digits @getMinutes()
    second = shift2digits @getSeconds()
    ms = shift2digits @getMilliseconds()

    return "#{year}#{month}#{day}#{hour}#{minute}#{second}#{ms}"
