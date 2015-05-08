#!/bin/bash

# 最新版本
# https://github.com/qidizi/linux-shells/blob/master/mysql-backup-by-root-crontab.sh

# 可以使用以下命令在后台测试:
# xxxxx.sh & 

# 配置root的定时任务crontab,比如:
# 每天03点自动备份mysql数据库
# 0 03 * * * /home/backup/mysql-backup-by-root-crontab.sh

# mysql 的备份脚本
# 备份原理:
# 1
#   列举所有的库名称;
# 2
#   列举每个库的每张表,除了指定忽略的库;
# 3
#   使用mysqldump 导出每一张表到文件:主机名/年月日/库/表.mysqldump.sql
# 4
#   验证每张表的sql文件是否包含完成标志;
# 5
#       压缩每个sql文件并删除本sql文件
# 6
#       强制删除超过x天的备份文件夹全部文件
# 7
#       发送处理日志到指定email
# 8
#       需要自行配置同步工具多处服务器备份

#----------mysql备份配置信息-------------
#数据库连接用户名
mysqlBackupUser="backuper"
#数据库连接用户的密码,不要包含'号,目前在命令行中输入密码,本人测试的ubuntu下密码会被替换成xxxx,如果防止在进程中暴露,可以my.cnf中指定
mysqlBackupPwd='password'
#连接主机总是使用 127.0.0.1的,请配置时注意

# 本shell日志文件路径是/var/log/本shell文件名.log,只保留每次运行的日志
# 指定不需要备份的数据库名称,每个名称使用()号包住,如指定不备份 abc.d 和 abc.e二个数据库,就拼写成"(abc.d)(abc.e)",名字不区分大小写
notBackupDatabases="(mysql)(information_schema)(performance_schema)"
# 指定不需要备份的表,格式如下: (库名 表名)
notBackupTables="(abc e)"

#备份sql保存的根目录,后面需要加/
backupRoot="/var/backup/hostname-mysql-data/"
# 删除x天前的备份的目录/文件:x天前备份的都会被删除,为了节省空间
deleteRootOutDays=30

#smtp发送email通知成败与你的配置和系统条件有关,如果没有收到email通知,请到日志中查找原因
#smtp发件人的email:mail from命令用到
smtpFrom="qq@qq.com"
#日志的收件人
smtpTo="qq@qq.com"
#日志收件标题,注意不要包含'
smtpSubject='mysql自动备份脚本执行信息'
#smtp登录用户,qq服务器是完整的email
smtpUser="qq@qq.com"
#smtp连接用户的密码,不能包含又引号防止shell出错
smtpPwd='qq'
#smtp://协议是固定的,只需要改变域名和端口即可,注意暂时不考虑兼容ssl连接
smtpHost="smtp://smtp.qq.com:25"

#=================配置结束行===============




SH_START=$(date +%s)
shName=$(basename $0)
shLogPath="/var/log/${shName}.log"
echo -e "${0}@$(date "+%F %T")\n" > $shLogPath

function myExit(){
    exitCode=$1
    appendLog "主机IP信息:\n$(ip -4 -o addr 2>&1)"
    appendLog "脚本总耗时$(expr $(date +%s) - ${SH_START})秒"
	
	if [ "${exitCode}" -ne "0" ];then
		appendLog "异常退出,请根据日志解决问题"
	fi
	
    ver=$(mailx -V 2>&1)

    if [ "$?" -ne "0" ];then
        appendLog "发送email通知需安装Heirloom mailx，出错信息:${ver}"
    else
        mailStart=$(date +%s)
        #发送email,目前使用的命令行输入密码的方式会在ps aux下暴露出来,如果需要考虑这个问题,可以研究mailx的选项,使用mail.rc的方式来配置
        mailInfo=$(cat ${shLogPath} | mailx -v -s "${smtpSubject}" -S from=${smtpFrom}  -S smtp-auth=login -S smtp=${smtpHost} -S smtp-auth-user=${smtpUser} -S smtp-auth-password="${smtpPwd}" ${smtpTo} 2>&1)
        # 无法附加发送过程的日志给email通知中,所以,只能保存到日志中,如果需要了解email的交互过程,请到日志文件中查看
        appendLog "发送email通知耗时$(expr $(date +%s) - ${mailStart})秒;交互记录如下:\n\n${mailInfo}"
    fi

    exit $exitCode
}

# 追加日志
function appendLog(){
    echo -e "${1}\n" >> $shLogPath
}

if [ ! -e "${backupRoot}" ];then
    mkInfo=$(mkdir -p $backupRoot 2>&1)

    if [ "$?" -ne "0" ];then
        appendLog "创建不存在的mysql备份总目录${backupRoot}:失败,${mkInfo}"
        myExit 1
    fi

elif [ ! -d "${backupRoot}" ];then
    appendLog "mysql备份路径${backupRoot}虽存在,但它不是目录"
    myExit 2
fi

#今天的备份目录
todayRoot="${backupRoot}$(date +%Y%m%d%H)/"

if [ ! -e "${todayRoot}" ];then
    mkInfo=$(mkdir $todayRoot 2>&1)

    if [ "$?" -ne "0" ];then
        appendLog "创建本轮的备份目录${todayRoot}:失败,${mkInfo}"
        myExit 3
    fi
fi

ver=$(mysql --version 2>&1)

if [ "$?" -ne "0" ];then
    appendLog "mysql命令异常:${ver}"
    myExit 4
fi

ver=$(mysqldump -V 2>&1)

if [ "$?" -ne "0" ];then
    appendLog "mysqldump命令异常:${ver}"
    myExit 5
fi

ver=$(tail --version 2>&1)

if [ "$?" -ne "0" ];then
    appendLog "tail命令异常:${ver}"
    myExit 6
fi

ver=$(tar  --version 2>&1)

if [ "$?" -ne "0" ];then
    appendLog "tar命令异常:${ver}"
    myExit 7
fi

databases=$(mysql --host=127.0.0.1 --user=${mysqlBackupUser}  --password="${mysqlBackupPwd}" --execute="show databases;"  --silent --skip-column-names --unbuffered  2>&1)

if [ "$?" -ne "0" ]; then
    appendLog "列举全部数据库名称异常:${databases}"
    myExit 8
else
    appendLog "数据库全部列表:\n${databases}"
fi


for database in $databases; do
    # 匹配时不区分大小写
    echo $notBackupDatabases|grep -i "(${database})" 2>&1 >/dev/null

    # 属于不需要备份的库
    if [ "$?" -eq "0" ];then
        appendLog "${database}库指定不备份"
        continue
    fi

    databaseRoot="${todayRoot}${database}/"

    if [ ! -e "${databaseRoot}" ];then
        mkInfo=$(mkdir $databaseRoot 2>&1)

        if [ "$?" -ne "0" ];then
            appendLog "创建${databaseRoot}库的备份目录异常:${mkInfo}"
            myExit 9
        fi
    fi

    tables=$(mysql --host=127.0.0.1 --user="${mysqlBackupUser}"  --password="${mysqlBackupPwd}" --execute="show tables from \`${database}\`;"  --silent --skip-column-names --unbuffered 2>&1)

        if [ "$?" -ne "0" ]; then
                appendLog "列举${database}库 全部表名异常:${tables}"
                myExit 10
        else
                appendLog "${database}库的全部表名:\n${tables}"
        fi

    for table in $tables; do
                #忽略备份文件
                echo $notBackupTables|grep -i "(${database} ${table})" 2>&1 >/dev/null

                # 属于不需要备份的库
                if [ "$?" -eq "0" ];then
                        appendLog "${database}库${table}表指定不备份"
                        continue
                fi

        sqlFile="${table}.sql"
        sqlPath="${databaseRoot}${sqlFile}"
        timeStart=$(date +%s)
        dumpInfo=$(mysqldump --host=127.0.0.1 --user=${mysqlBackupUser} --password="${mysqlBackupPwd}" --dump-date --comments --quote-names --result-file=${sqlPath} --quick  --databases ${database} --tables ${table} 2>&1)

        if [ "$?" -ne "0" ];then
            appendLog "mysqldump导出${database}库${table}表异常:${dumpInfo}"
            myExit 11
        fi

        sok="${database}库${table}表dump到${sqlPath}成功:耗时$(expr $(date +%s) - ${timeStart})秒;查找dump成功的'Dump completed'字符标志:"
        tail --lines=10 "${sqlPath}" |grep "\-\- Dump completed" 2>&1 > /dev/null

        if [ "$?" -ne "0" ];then
                sok="${sok}无，请登录ssh确认本备份情况"
        else
                sok="${sok}存在，据此判断备份成功了"
                tarFile="${sqlFile}.tar.bz2"
                timeStart=$(date +%s)                sok="${sok};打包压缩${sqlFile}(成功后删除之)成${tarFile}:"
                tarInfo=$(tar --create --remove-files --bzip2 --absolute-names --directory="${databaseRoot}"   --add-file="${sqlFile}" --file="${databaseRoot}${tarFile}")

                if [ "$?" -ne "0" ];then 
					sok="${sok}出错,${tarInfo}"
                else
					sok="${sok}成功"
                fi

                sok="${sok},耗时$(expr $(date +%s) - ${timeStart})秒;"

        fi

        appendLog "${sok}"
    done

done

appendLog "\n ------数据库备份操作全部完成------\n"
#开始清理大于x天的备份

daysDir=$(ls --almost-all --ignore-backups --indicator-style=slash -1 "${backupRoot}" 2>&1)

for bkDir in $daysDir;do
    bkDir="${backupRoot}${bkDir}"

    if [ ! -d "${bkDir}" ];then
        continue
    fi

    dirName=$(basename $bkDir)
    #测试目录名是否规定的格式
    echo $dirName | grep -P "^\d{10}$" 2>&1 >/dev/null

    if [ "$?" -ne "0" ];then
        continue
    fi

    outDay=$(date --date="-${deleteRootOutDays}day" "+%Y%m%d00")

    #如果文件时间小于这个过期时间那么就强制删除整个目录
    if [ "${dirName}" -lt "${outDay}" ];then
        rmInfo=$(rm --force --preserve-root --recursive "${bkDir}" 2>&1)
		rmOk="成功"
		
		if [ "$?" -ne "0" ];then
			rmOk="失败 -- ${rmInfo}"
		fi
		
        appendLog "备份目录${bkDir}超过 ${deleteRootOutDays}天(${dirName} < ${outDay}):强制删除${rmOk}"
    fi

done

appendLog "------删除过期备份文件夹操作完成----"
appendLog "空间使用情况如下:\n $(df -h 2>&1)"
appendLog "本轮备份占用空间情况:\n $(du -hs ${todayRoot} 2>&1)"
myExit 0
