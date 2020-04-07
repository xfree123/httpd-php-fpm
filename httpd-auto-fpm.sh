#!/bin/bash
# Auto install Apache HTTP server on centos 7
# Create Date: 05/04/2020 by Xfree

svip=$(wget http://ipecho.net/plain -O - -q ; echo)
if [ $(id -u) != "0" ]; then
    echo "Error: You have to login by user root!"
    exit
fi
# Update & install some tools
yum -y update
yum -y install epel-release
yum -y install nano wget zip unzip net-tools

# php version: remi-php74, remi-php73, remi-php72 remi-php71, remi-php70, remi-php54, remi-php56
# edit here to change php version
phpversion="remi-php74"

echo "------------------Now Install apache http server-------------"

yum -y install httpd httpd-devel
echo "ServerName 127.0.0.1" >> /etc/httpd/conf/httpd.conf
systemctl enable httpd
systemctl start httpd
# Open firewall for http service, change SSH port
firewall-cmd --permanent --add-service=http
firewall-cmd --permanent --add-service=https
firewall-cmd --permanent --add-port=22225/tcp
firewall-cmd --permanent --remove-service=ssh
firewall-cmd --reload
sed -i 's/#Port 22/Port 22225/g' /etc/ssh/sshd_config
systemctl restart sshd

#Change Localtime to GMT +7
mv /etc/localtime /etc/localtime.bak
ln -s /usr/share/zoneinfo/Asia/Bangkok /etc/localtime

#Add google DNS
#echo "DNS1=8.8.8.8" >> /etc/sysconfig/network-scripts/ifcfg-eth0

echo "------------------Install php and extension-------------------"
wget https://rpms.remirepo.net/enterprise/remi-release-7.rpm
rpm -Uvh remi-release-7.rpm
yum install yum-utils -y
yum-config-manager --enable $phpversion >> /dev/null 2>&1

yum -y install php php-fpm php-common php-gd php-json php-mbstring php-mcrypt php-opcache php-pecl-geoip php-pecl-redis php-xml php-mysqlnd php-cli php-soap php-pecl-memcached php-pecl-zip php-pecl-zip php-pear php-devel
systemctl restart httpd
echo "------------------Install imagick------------------------------"
yum -y install gcc make automake ImageMagick ImageMagick-devel

#pecl install imagick
yes '' | pecl install imagick
chmod 775 /usr/lib64/php/modules/imagick.so

echo "; Enable imagick extension for php" > /etc/php.d/60-imagick.ini
echo "extension=imagick.so" >> /etc/php.d/60-imagick.ini

echo "-------------------Install MySQL server-----------------------"
yum -y install mariadb mariadb-server

systemctl start mariadb
systemctl enable mariadb

config=".my.cnf.$$"
command=".mysql.$$"

trap "interrupt" 1 2 3 6 15
sqlrootpassword="61Pdf0kJ"
mysqladmin -u root password $sqlrootpassword
rootpass=
echo_n=
echo_c=
basedir=
bindir=
echo $sqlrootpassword > /root/sql_root_password.txt
parse_arg()
{
  echo "$1" | sed -e 's/^[^=]*=//'
}

parse_arguments()
{
  pick_args=
  if test "$1" = PICK-ARGS-FROM-ARGV
  then
    pick_args=1
    shift
  fi

  for arg
  do
    case "$arg" in
      --basedir=*) basedir=`parse_arg "$arg"` ;;
      --no-defaults|--defaults-file=*|--defaults-extra-file=*)
        defaults="$arg" ;;
      *)
        if test -n "$pick_args"
        then
          args="$args $arg"
        fi
        ;;
    esac
  done
}

find_in_basedir()
{
  return_dir=0
  found=0
  case "$1" in
    --dir)
      return_dir=1; shift
      ;;
  esac

  file=$1; shift

  for dir in "$@"
  do
    if test -f "$basedir/$dir/$file"
    then
      found=1
      if test $return_dir -eq 1
      then
        echo "$basedir/$dir"
      else
        echo "$basedir/$dir/$file"
      fi
      break
    fi
  done

  if test $found -eq 0
  then
      # Test if command is in PATH
      $file --no-defaults --version > /dev/null 2>&1
      status=$?
      if test $status -eq 0
      then
        echo $file
      fi
  fi
}

cannot_find_file()
{
  echo
  echo "FATAL ERROR: Could not find $1"

  shift
  if test $# -ne 0
  then
    echo
    echo "The following directories were searched:"
    echo
    for dir in "$@"
    do
      echo "    $dir"
    done
  fi

  echo

}

parse_arguments PICK-ARGS-FROM-ARGV "$@"

if test -n "$basedir"
then
  print_defaults=`find_in_basedir my_print_defaults bin extra`
  echo "print: $print_defaults"
  if test -z "$print_defaults"
  then
    cannot_find_file my_print_defaults $basedir/bin $basedir/extra
    exit 1
  fi
else
  print_defaults="/usr/bin/my_print_defaults"
fi

if test ! -x "$print_defaults"
then
  cannot_find_file "$print_defaults"
  exit 1
fi

parse_arguments `$print_defaults $defaults client client-server client-mariadb`
parse_arguments PICK-ARGS-FROM-ARGV "$@"

# Configure paths to support files
if test -n "$basedir"
then
  bindir="$basedir/bin"
elif test -f "./bin/mysql"
  then
  bindir="./bin"
else
  bindir="/usr/bin"
fi

mysql_command=`find_in_basedir mysql $bindir`
if test -z "$mysql_command"
then
  cannot_find_file mysql $bindir
  exit 1
fi

set_echo_compat() {
    case `echo "testing\c"`,`echo -n testing` in
	*c*,-n*) echo_n=   echo_c=     ;;
	*c*,*)   echo_n=-n echo_c=     ;;
	*)       echo_n=   echo_c='\c' ;;
    esac
}

validate_reply () {
    ret=0
    if [ -z "$1" ]; then
	reply=y
	return $ret
    fi
    case $1 in
        y|Y|yes|Yes|YES) reply=y ;;
        n|N|no|No|NO)    reply=n ;;
        *) ret=1 ;;
    esac
    return $ret
}

prepare() {
    touch $config $command
    chmod 600 $config $command
}

do_query() {
    echo "$1" >$command
    #sed 's,^,> ,' < $command  # Debugging
    $mysql_command --defaults-file=$config <$command
    return $?
}

basic_single_escape () {
    echo "$1" | sed 's/\(['"'"'\]\)/\\\1/g'
}

make_config() {
    echo "# mysql_secure_installation config file" >$config
    echo "[mysql]" >>$config
    echo "user=root" >>$config
    esc_pass=`basic_single_escape "$rootpass"`
    echo "password='$esc_pass'" >>$config
    #sed 's,^,> ,' < $config  # Debugging
}

get_root_password() {
    status=1
    rootpass=$sqlrootpassword
	make_config
	do_query ""
	status=$?
    
    echo "OK, successfully used root password, moving on..."
    echo
}

set_root_password() {
        return 0
}

remove_anonymous_users() {
    do_query "DELETE FROM mysql.user WHERE User='';"
    if [ $? -eq 0 ]; then
	echo " ... Success!"
    else
	echo " ... Failed!"
	clean_and_exit
    fi

    return 0
}

remove_remote_root() {
    do_query "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
    if [ $? -eq 0 ]; then
	echo " ... Success!"
    else
	echo " ... Failed!"
    fi
}

remove_test_database() {
    echo " - Dropping test database..."
    do_query "DROP DATABASE IF EXISTS test;"
    if [ $? -eq 0 ]; then
	echo " ... Success!"
    else
	echo " ... Failed!  Not critical, keep moving..."
    fi

    echo " - Removing privileges on test database..."
    do_query "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%'"
    if [ $? -eq 0 ]; then
	echo " ... Success!"
    else
	echo " ... Failed!  Not critical, keep moving..."
    fi

    return 0
}

reload_privilege_tables() {
    do_query "FLUSH PRIVILEGES;"
    if [ $? -eq 0 ]; then
	echo " ... Success!"
	return 0
    else
	echo " ... Failed!"
	return 1
    fi
}

interrupt() {
    echo
    echo "Aborting!"
    echo
    cleanup
    stty echo
    exit 1
}

cleanup() {
    echo "Cleaning up..."
    rm -f $config $command
}

# Remove the files before exiting.
clean_and_exit() {
	cleanup
	exit 1
}

# The actual script starts here

prepare
set_echo_compat

echo "Secured your SQL server"


get_root_password



#
# Remove anonymous users
#

echo "By default, a MariaDB installation has an anonymous user, allowing anyone"
echo "to log into MariaDB without having to have a user account created for"
echo "them.  This is intended only for testing, and to make the installation"
echo "go a bit smoother.  You should remove them before moving into a"
echo "production environment."
echo

remove_anonymous_users

echo


#
# Disallow remote root login
#

echo "Normally, root should only be allowed to connect from 'localhost'.  This"
echo "ensures that someone cannot guess at the root password from the network."
echo

remove_remote_root


#
# Remove test database
#

echo "By default, MariaDB comes with a database named 'test' that anyone can"
echo "access.  This is also intended only for testing, and should be removed"
echo "before moving into a production environment."
echo


    remove_test_database

#
# Reload privilege tables
#

echo "Reloading the privilege tables will ensure that all changes made so far"
echo "will take effect immediately."
echo
reload_privilege_tables


cleanup
echo
echo "All done!  If you've completed all of the above steps, your MariaDB"
echo "installation should now be secure."
echo
echo "Thanks for using MariaDB!"


rm -f /etc/php-fpm.conf

cat > "/etc/php-fpm.conf" <<END
;;;;;;;;;;;;;;;;;;;;;
; FPM Configuration ;
;;;;;;;;;;;;;;;;;;;;;
include=/etc/php-fpm.d/*.conf

[global]
pid = /var/run/php-fpm/php-fpm.pid
error_log = /var/log/php-fpm.log
emergency_restart_threshold = 10
emergency_restart_interval = 1m
process_control_timeout = 10s

END

rm -f /etc/php-fpm.d/*.*

cat > "/etc/php-fpm.d/www.conf" <<END
[www]
;listen = 127.0.0.1:9000
listen = /var/run/php-fpm/php-fpm.sock
listen.allowed_clients = 127.0.0.1
listen.owner = apache
listen.group = apache 
user = apache
group = apache
pm = ondemand
pm.max_children = 20
; default: min_spare_servers + (max_spare_servers - min_spare_servers) / 2
pm.start_servers = 10
pm.min_spare_servers = 5
pm.max_spare_servers = 15
pm.max_requests = 500
pm.status_path = /php_status
request_terminate_timeout = 100s
pm.process_idle_timeout = 10s;
request_slowlog_timeout = 4s
slowlog = /var/log/php-fpm-slow.log
rlimit_files = 131072
rlimit_core = unlimited
catch_workers_output = yes
env[HOSTNAME] = $HOSTNAME
env[PATH] = /usr/local/bin:/usr/bin:/bin
env[TMP] = /tmp
env[TMPDIR] = /tmp
env[TEMP] = /tmp
php_admin_value[error_log] = /var/log/php-fpm-error.log
php_admin_flag[log_errors] = on
php_value[session.save_handler] = files
php_value[session.save_path] = /var/lib/php/session

END

#Custom php value to work with wordpress_
sed -i 's/^max_execution_time.*/max_execution_time=600/' /etc/php.ini
sed -i 's/^max_input_time.*/max_input_time=600/' /etc/php.ini
sed -i 's/^post_max_size.*/post_max_size=128M/' /etc/php.ini
sed -i 's/^upload_max_filesize.*/upload_max_filesize=128M/' /etc/php.ini
sed -i "s/^\;date.timezone.*/date.timezone=\'Asia\/Bangkok\'/" /etc/php.ini
sed -i "s/^\;max_input_vars.*/max_input_vars=3000/" /etc/php.ini

#config fpm module for apache
sed -i "s/LoadModule mpm_prefork_module modules\/mod_mpm_prefork.so/\#LoadModule mpm_prefork_module modules\/mod_mpm_prefork.so/" /etc/httpd/conf.modules.d/00-mpm.conf
sed -i "s/#LoadModule mpm_event_module modules\/mod_mpm_event.so/LoadModule mpm_event_module modules\/mod_mpm_event.so/" /etc/httpd/conf.modules.d/00-mpm.conf

mv /etc/httpd/conf.d/php.conf /etc/httpd/conf.d/php.conf.bak

cat > "/etc/httpd/conf.d/php-fpm.conf" <<END
#
# The following lines prevent .user.ini files from being viewed by Web clients.
#
<Files ".user.ini">
    <IfModule mod_authz_core.c>
        Require all denied
    </IfModule>
    <IfModule !mod_authz_core.c>
        Order allow,deny
        Deny from all
        Satisfy All
    </IfModule>
</Files>

#
# Allow php to handle Multiviews
#
# Proxy declaration
<Proxy "unix:/var/run/php-fpm/php-fpm.sock|fcgi://php-fpm">
	# we must declare a parameter in here (doesn't matter which) or it'll not register the proxy ahead of time
    	ProxySet disablereuse=off
</Proxy>

# Redirect to the proxy
<FilesMatch \.php$>
	SetHandler proxy:fcgi://php-fpm
</FilesMatch>
AddType text/html .php

#
# Add index.php to the list of files that will be served as directory
# indexes.
#
DirectoryIndex index.php

# mod_php options
#<IfModule  mod_php7.c>
    #
    # Cause the PHP interpreter to handle files with a .php extension.
    #
#    <FilesMatch \.(php|phar)$>
#        SetHandler application/x-httpd-php
#    </FilesMatch>

    #
    # Uncomment the following lines to allow PHP to pretty-print .phps
    # files as PHP source code:
    #
    #<FilesMatch \.phps$>
    #    SetHandler application/x-httpd-php-source
    #</FilesMatch>

    #
    # Apache specific PHP configuration options
    # those can be override in each configured vhost
    #
#    php_value session.save_handler "files"
#    php_value session.save_path    "/var/lib/php/session"
#    php_value soap.wsdl_cache_dir  "/var/lib/php/wsdlcache"

    #php_value opcache.file_cache   "/var/lib/php/opcache"
#</IfModule>

END

mkdir -p /home/websites/sample.vhost/public_html
mkdir -p /home/websites/sample.vhost/logs
chown -R apache:apache /home/websites/
ln -s /home/websites/ /var/www/websites

cat > "/etc/httpd/conf.d/sample.vhost.conf" <<END
<VirtualHost *:80>

    ServerName 		sample.vhost
    ServerAlias 	www.sample.vhost
    DocumentRoot 	/var/www/websites/sample.vhost/public_html
    ErrorLog 		/var/www/websites/sample.vhost/logs/sample.vhost_error.log
    CustomLog 		/var/www/websites/sample.vhost/logs/sample.vhost_access.log combined
	<Directory "/var/www/websites/sample.vhost/public_html">
    Options Indexes FollowSymLinks
    AllowOverride All
    Require all granted
</Directory>
</VirtualHost>
END

echo "<?php phpinfo(); ?>" > /var/www/websites/sample.vhost/public_html/info.php
cat > "/var/www/html/index.html" <<END
<head>
<h1 align="center"> TEST SITE ROOT </h1>
</head>
<body>
<h2> you are welcome </h2>
</body>
END
cat > "/var/www/websites/sample.vhost/public_html/index.html" <<END
<head>
<h1 align="center"> TEST SITE VHOST </h1>
</head>
<body>
<h2> you are welcome </h2>
</body>
END

systemctl enable php-fpm
systemctl start php-fpm
systemctl restart httpd

echo "DONE"
echo "See root folder for sql root password"
echo
echo "Go to http://$svip/ or http://$svip/info.php  for more infomation"
