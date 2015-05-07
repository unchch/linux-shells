#!/bin/bash

# https://github.com/qidizi/linux-shells/blob/master/mysql-backup-by-root-crontab.sh
# 请把本文件加入root的tabcron,比如:
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
#数据库连接用户的密码,不要包含'号
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

shName=$(basename $0)
shLogPath="/var/log/${shName}.log"
echo -e "By ${0} @ $(date "+%F %T")\n" > $shLogPath

function myExit(){
    exitCode=$1
    appendLog "退出脚本时间:$(date +%F/%T)"
    appendLog "服务器IP信息:\n$(ip -4 -o addr 2>&1)"
    ver=$(mailx -V 2>&1)

    if [ "$?" -ne "0" ];then
        appendLog "用来通过smtp发送email的命令mailx无法使用,请安装,如centos使用yum install mailx,注意必须是 Heirloom mailx这个版本,跳过发送email通知的步骤,正确安装mailx后就可以收到email通知了,测试时出错信息:${ver}"
    else
                startTime="$(date +%F/%T)"
        #发送email
        mailInfo=$(cat ${shLogPath} | mailx -v -s "${smtpSubject}" -S from=${smtpFrom}  -S smtp-auth=login -S smtp=${smtpHost} -S smtp-auth-user=${smtpUser} -S smtp-auth-password="${smtpPwd}" ${smtpTo} 2>&1)
        # 无法附加发送过程的日志给email通知中,所以,只能保存到日志中,如果需要了解email的交互过程,请到日志文件中查看
        appendLog "使用mailx通过smtp发送email的耗时:从 ${startTime} 至 $(date +%F/%T);交互记录如下:\n\n${mailInfo}"
    fi

    exit $exitCode
}

# 追加日志
function appendLog(){
    echo -e "${1}\n" >> $shLogPath
}

if [ ! -e "${backupRoot}" ];then
    appendLog "备份根目录 ${backupRoot} 不存在,尝试创建"
    mkInfo=$(mkdir -p $backupRoot 2>&1)

    if [ "$?" -ne "0" ];then
        appendLog "创建目录 ${backupRoot} 失败:${mkInfo}"
        myExit 1
    fi

elif [ ! -d "${backupRoot}" ];then
    appendLog "备份根目录 ${backupRoot} 已经存在,但是它并非是一个目录,终止"
    myExit 2
fi

#今天的备份目录
todayRoot="${backupRoot}$(date +%Y%m%d%H)/"

if [ ! -e "${todayRoot}" ];then
    mkInfo=$(mkdir $todayRoot 2>&1)

    if [ "$?" -ne "0" ];then
        appendLog "尝试创建本轮的备份目录 ${todayRoot} 失败,终止:${mkInfo}"
        myExit 3
    fi
fi

appendLog "本轮的备份主目录:${todayRoot}"
ver=$(mysql --version 2>&1)

if [ "$?" -ne "0" ];then
    appendLog "测试用来连接数据库的命令mysql的版本时出错,终止:${ver}"
    myExit 4
fi

ver=$(mysqldump -V 2>&1)

if [ "$?" -ne "0" ];then
    appendLog "测试mysqldump命令出错,终止:${ver}"
    myExit 5
fi

ver=$(tail --version 2>&1)

if [ "$?" -ne "0" ];then
    appendLog "测试tail命令时出错,终止:${ver}"
    myExit 6
fi

ver=$(tar  --version 2>&1)

if [ "$?" -ne "0" ];then
    appendLog "测试tar命令时出错,终止:${ver}"
    myExit 7
fi

databases=$(mysql --host=127.0.0.1 --user=${mysqlBackupUser}  --password="${mysqlBackupPwd}" --execute="show databases;"  --silent --skip-column-names --unbuffered  2>&1)

if [ "$?" -ne "0" ]; then
    appendLog "尝试使用配置信息列举出mysql的全部数据库名称时出错,终止:${databases}"
    myExit 8
else
    appendLog "全部的数据库名称列表如下:\n${databases}"
fi


for database in $databases; do
    # 匹配时不区分大小写
    echo $notBackupDatabases|grep -i "(${database})" 2>&1 >/dev/null

    # 属于不需要备份的库
    if [ "$?" -eq "0" ];then
        appendLog "数据库 ${database} 被指定不需要备份,跳过"
        continue
    fi

    databaseRoot="${todayRoot}${database}/"

    if [ ! -e "${databaseRoot}" ];then
        mkInfo=$(mkdir $databaseRoot 2>&1)

        if [ "$?" -ne "0" ];then
            appendLog "尝试创建数据库 ${databaseRoot} 的备份目录失败,终止:${mkInfo}"
            myExit 9
        fi
    fi

    tables=$(mysql --host=127.0.0.1 --user="${mysqlBackupUser}"  --password="${mysqlBackupPwd}" --execute="show tables from \`${database}\`;"  --silent --skip-column-names --unbuffered 2>&1)

        if [ "$?" -ne "0" ]; then
                appendLog "尝试使用配置信息列举数据库 ${database} 全部的表名时出错,终止:${tables}"
                myExit 10
        else
                appendLog "数据库${database}全部表的列表如下:\n${tables}"
        fi

    for table in $tables; do
		#忽略备份文件
		echo $notBackupTables|grep -i "(${database} ${table})" 2>&1 >/dev/null

		# 属于不需要备份的库
		if [ "$?" -eq "0" ];then
			appendLog "数据库 ${database} 下的 ${table} 表被指定不需要备份,跳过"
			continue
		fi
	
        sqlPath="${databaseRoot}${table}.sql"
        timeStart="$(date +%F/%T)"
        dumpInfo=$(mysqldump --host=127.0.0.1 --user=${mysqlBackupUser} --password="${mysqlBackupPwd}" --dump-date --comments --quote-names --result-file=${sqlPath} --quick  --databases ${database} --tables ${table} 2>&1)

        if [ "$?" -ne "0" ];then
            appendLog "尝试使用mysqldump导出数据库${database}中的表 ${table} 失败,终止:${dumpInfo}"
            myExit 11
        else
            appendLog "数据库 ${database}的表 ${table} dump到文件 ${sqlPath} 成功:${dumpInfo}; 耗时: 从 ${timeStart} 至 $(date +%F/%T)"

            tail --lines=10 "${sqlPath}" |grep "\-\- Dump completed" 2>&1 > /dev/null

            if [ "$?" -ne "0" ];then
                appendLog "dump文件${sqlPath}没有结束行用来表示成功dump的 'Dump completed' 标志字符,请登录ssh查看此文件是否备份成功"
            else
                appendLog "dump文件${sqlPath}从文件内容中检测到成功备份的标志字符'Dump completed',自动判断应该备份成功了"
            fi

        fi

    done

done

appendLog "\n ------数据库备份操作全部完成------\n"

# 开始压缩,把压缩放到备份结束是防止压缩时间过长,如果出现锁表,会影响网站运行
sqls=$(ls --almost-all --ignore-backups --indicator-style=slash -1 ${todayRoot}*/*.sql 2>&1)

for path in $sqls; do
    sqlDir=$(dirname $path)
    sql=$(basename $path)
        appendLog "压缩 $path 开始于 $(date +%F/%T)"
    tarInfo=$(tar --create --remove-files --bzip2 --absolute-names --directory="${sqlDir}"   --add-file="${sql}" --file="${path}.tar.bz2")

    if [ "$?" -ne "0" ];then
        appendLog "压缩出错:\n${tarInfo}"
    else
        appendLog "压缩成功并删除源文件"
    fi

        appendLog "压缩完成于 $(date +%F/%T)"
	
done

appendLog "------压缩操作全部完成-----"
#开始清理大于x天的备份

daysDir=$(ls --almost-all --ignore-backups --indicator-style=slash -1 "${backupRoot}" 2>&1)

for bkDir in $daysDir;do
    bkDir="${backupRoot}${bkDir}"

    if [ ! -d "${bkDir}" ];then
        appendLog "删除过期的备份文件操作时,检测到${bkDir}不是一个目录,跳过"
        continue
    fi

    dirName=$(basename $bkDir)
    #测试目录名是否规定的格式
    echo $dirName | grep -P "^\d{10}$" 2>&1 >/dev/null

    if [ "$?" -ne "0" ];then
        appendLog "准备删除过期备份目录${bkDir}时,检测到待删除目录名不是类2015040517(年4月2日2时2)格式的10位数字,跳过"
        continue
    fi

    outDay=$(date --date="-${deleteRootOutDays}day" "+%Y%m%d00")

    #如果文件时间小于这个过期时间那么就强制删除整个目录
    if [ "${dirName}" -lt "${outDay}" ];then
        rmInfo=$(rm --force --preserve-root --recursive "${bkDir}" 2>&1)
        appendLog "检测到一个过期备份目录 ${bkDir},已经超过 ${deleteRootOutDays} 天,也就是从备份目录名称上判断,它是小于${outDay}了 ,现被强制删除,删除状态(0为成功):${?} ;删除返回信息:${rmInfo};"
    fi

done

appendLog "------完成清理过期备份文件夹操作----"
appendLog "空间使用情况如下:\n $(df -h 2>&1)"
appendLog "当前备份文件占用空间情况:\n $(du -hs ${todayRoot} 2>&1)"
myExit 0
