#!/bin/bash

# 最新版本:https://github.com/qidizi/linux-shells/blob/master/rsync-crontab-via-ssh.sh

# 脚本说明:
# 这是一个使用rsync进行不同主机之间增量备份文件的定时脚本
# 为了方便,互相之间都是使用ssh来传递,不使用rsync的守护进程;
# 配合定时+同时只能允许一个线程存在的逻辑;
# 必须是3.1或以上版本;

# 用途:
# 大概达到的目的是,保证删除源文件时不会删除备份中的相同路径文件,而更新内容或是新加文件都会同步过来,
# 这样就可以保证能找回不小心删除文件的可能;

# 配置区域

# rsync命令的配置
# 指定被备份的文件的ssh用户@主机ip,目录路径,每个目录格式是 :'目录1路径'; 多个目录之间使用空格分开,如 :'目录1' :'目录2',注意目录后面不要加/;
srcDirPaths="rsyncer@192.168.10.57:'/var/www/q.qidizi.net' :'/var/www/b.qidizi.com'";
# 用来存放备份文件的保存目录
desDirPath=/home/backup/qidizi-9/var-www/
# 被备份主机的ssh端口
remoteSshPort=22
# 被备份主机用来ssh登录的私key
remoteSshKey=/home/backup/qidizi-9-rsync-ssh-key
# 忽略备份的路径,详细语法见:https://download.samba.org/pub/rsync/rsync.html 的 FILTER RULES 章节;
# 排除是 --exclude="要排除的路径或是正则"
filter='--exclude="*/.ssh/" --exclude="*/.git/" --exclude="*/.bash_logout" --exclude="*/.bashrc" --exclude="*/.profile" --exclude="*/.svn/"'

# smtp配置
#smtp发送email通知成败与你的配置和系统条件有关,如果没有收到email通知,请到日志中查找原因
#smtp发件人的email:mail from命令用到
smtpFrom="qidizi@qq.com"
#日志的收件人
smtpTo="qidizi@qq.com"
#日志收件标题,注意不要包含'
smtpSubject='使用rsync备份网站文件的执行信息[linux通知]'
#smtp登录用户,qq服务器是完整的email
smtpUser="qidizi@qq.com"
#smtp连接用户的密码,不能包含又引号防止shell出错
smtpPwd='qq密码'
#只需要改变域名和端口即可,注意暂时不考虑兼容ssl连接
smtpHost="smtp.qq.com"
smtpPort=25

# 配置区域


# 配置root的crontab -e 定时任务,比如:
# 每天03点自动运行
# 0 03 * * * /home/backup/abc.sh


# rsync参数说明:
# --no-checksum: 快速检测模式(最后修改时+大小)已经足够,checksum文件内容校验太浪费cpu没必要使用;
#使用局域网传送,不需要压缩archive
#低版本没有remote-option选项
# --human-readable: 提示中的容量大小单位使用人类容易懂的单位
# --times: 保留最后修改时间,尽量使用最后修改时间+大小来判断二处文件是否更改来决定是否启动同步;
# -verbose 数量越多,显示的详细说明越多,最多好像是3个;
# --whole-file 同步文件时使用重新传递整个文件的方式,而不是通过计算文件的变化来传递不同的,对于局域网传递来说,启用这个占用网络,但是节省cpu,在同一台机器不同的目录同步时,默认启用;
# src是目录时,必须指定-recursive参数,否则目录会被忽略,因为默认只能传文件,src目录路径后面跟/时表示只传递目录子内容的结构,但不包括本身(多子起点多分支),类似 cp -r src/*;而不跟/时,表示传递包含目录的本身(唯一自起点多分支),类似cp -r src;
# --update:如果备份的文件新过被备份文件,就会跳过,如des的文件新过src的,就不会把src的文件替换掉des中的;这种情况只有人工修改备份文件才需要,一般是问题无条件保留src的内容是对;
# 希望指定多个被备份目录时写法是  :目录1 :目录2

SH_START=$(date +%s)
shName=$(basename $0)
# 本脚本运行时的日志路径
localLog="/var/log/${shName}.log.html"

# 同一时间只允许运行一个实例,否则后面运行的实例会自动退出
# 必须是绝对路径才允许,这样根据路径来判断是否有其它实例就绝对点

shLists=$(ps -f -C "${shName}");
# 管理会产生子shell
shLists=$(echo -e "${shLists}" | grep "${0}");
shCount=$(echo -e "${shLists}" | wc -l);

if [[ "$0" != /* ]];then
	echo '<span style="color:red;">请使用绝对路径(以/开头)来运行本shell,而不是:'${0}'</span>' >> $localLog
	exit 2;
elif [[ "$0" == */./* ]];then
	echo '<span style="color:red;">禁止包含相对路径(/./)来运行本shell:'${0}'</span>' >> $localLog
	exit 3;
elif [[ "$0" == */../* ]];then
	echo '<span style="color:red;">禁止包含相对路径(/../)来运行本shell:'${0}'</span>' >> $localLog
	exit 4;
# 检测是否已经有实例运行了.
elif [ "${shCount}" -gt "1" ];then	
	echo -e '<span style="color:red;">本脚本同一时间只允许运行一个实例,后面启动的实例自动结束,当前实例个数(含自己):'"\n${shLists}"'</span>' >> $localLog
	exit 5;
fi
# 同一时间只允许运行一个实例,否则后面运行的实例会自动退出

echo -e "${0}@$(date "+%F %T")\n" > $localLog

# 测试是否有telnet
cmdInfo=$(which telnet 2>&1)

if [ "${?}" -ne "0" ];then
	echo -e '发送email需要telnet命令,请先安装' >> $localLog;
	exit 1;
fi

# rsync同步的命令行,因为参数比较多,所以,就不使用参数配置的方式了;
cmd='rsync  --rsh='$(echo "'")'ssh -2 -4 -p '${remoteSshPort}' -i '${remoteSshKey}' -v'$(echo "'")'  '${filter}'  --whole-file --no-checksum --human-readable --times --omit-dir-times --recursive --log-file="'${localLog}'" '${srcDirPaths}' '${desDirPath}
# 这里转义比较多,目前自己使用这种方式来使用,可能还有更加好的方式,不能直接${cmd},否则会提示-2不是rsync的选项,估计是解析时,把""号 吃掉 了;
cmdOut=$(echo -e "${cmd}"|/bin/bash 2>&1);

if [ "${?}" -ne "0" ];then
	echo -e "<span style=\"color:red;\">rsync同步出错:\n${cmdOut}\n</span>" >> "${localLog}";
else
	echo -e '<span style="color:green;">rsync同步完成</span>' >> "${localLog}";
fi

echo -e "被备份的目录是:${srcDirPaths}\n\n用来保存备份文件机器空间:\n$(df -h)\n\n当前备份目录占用情况:\n$(du -hs ${desDirPath})\n\n备份主机IP信息:\n$(ip -4 -o addr 2>&1)\n\n脚本总耗时$(expr $(date +%s) - ${SH_START})秒" >> "${localLog}";



# 使用telnet通过esmtp发送email内容的funciton参数顺序 "smtp-host" "smtp-port" "smtp-user" "smtp-pwd" "mail-from" "rcpt-to" "标题" "内容"
function esmtp() {
        # telnet 二次命令之间需要sleep
        cmdTest=$(which "telnet" 2>&1);

        if [ "$?" -ne "0" ];then
                echo 'esmtp函数需要telnet命令,请先安装!';
                return 1;
        fi

        sleepSec=1;

        (
                bid=$(date +%s);
                echo 'ehlo qidizi.com';#打招呼
                sleep ${sleepSec};
                echo 'auth login';
                sleep ${sleepSec};
                echo ${3}|base64;
                sleep ${sleepSec};
                echo ${4}|base64;
                sleep ${sleepSec};
                echo 'MAIL FROM: '${5};
                sleep ${sleepSec};
                echo 'RCPT TO: '${6};
                sleep ${sleepSec};
                echo 'data';
                sleep ${sleepSec};
                echo 'MIME-Version: 1.0';
                echo 'Date: '$(date -R);
                echo 'Subject: =?UTF-8?B?'$(echo ${7}|base64)'?=';
                echo 'From: =?UTF-8?B?'$(echo ${5}|base64)'?= <'${5}'>';
                echo 'To: =?UTF-8?B?'$(echo ${6}|base64)'?= <'${6}'>';
                echo 'Content-Type: multipart/alternative; boundary='${bid};
                echo "";
                echo '--'${bid};
                echo 'Content-Type: text/plain; charset=UTF-8';
                echo 'Content-Transfer-Encoding: base64';
                echo "";
                echo '你的服务器不支持显示html格式信件内容'|base64;
                echo '--'${bid};
                echo 'Content-Type: text/html; charset=UTF-8';
                echo 'Content-Transfer-Encoding: base64';
                echo "";
                echo -e "${8}"|base64;
                echo '--'${bid}'--';
                sleep ${sleepSec};
                echo '.';
                sleep ${sleepSec};
                echo 'quit';
        )|telnet ${1} ${2}
        return 0;
}

mailInfo=$(esmtp ${smtpHost} ${smtpPort} ${smtpUser} ${smtpPwd} ${smtpFrom} ${smtpTo} "${smtpSubject}" "<pre>$(cat ${localLog})</pre>" 2>&1);
echo -e "发送email通知交互记录如下:\n\n${mailInfo}" >> $localLog;
		
exit 0;
