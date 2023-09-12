#!/bin/bash

# This bash file is to create WordPress site using Cyberpanel CLI and WP-CLI
# Make sure Cyberpanel and WP-CLI have been installed on your server before use this file
# Author: Akah Martono (www.subarkah.com)

# Only can run by root
if [[ "$(whoami)" != root ]]; then
	echo "Only user root can run this script."
	exit 1
fi

# These parameters are rarely changed, so let's make it as constant variables 
cp_package="default"
cp_website_limit=1
cp_php_version="8.0"
cp_ssl=1
cp_dkim=0
cp_openBasedir=1
wp_locale="en_US"
timezone="Asia/Jakarta"

function validate_username () {
    local username="$1"
    local regex="^[a-zA-Z0-9_]{3,16}$"
    if ! [[ $username =~ $regex ]]; then
        echo "Invalid username: $username"
        return 1
    fi
    return 0
}

function validate_cp_username () { 
    validate_username $cp_username || return 1

    # get json of cyberpanel user list
    local json_users=$(cyberpanel listUsers)

    # replace \" with "
    json_users=${json_users//'\"'/'"'}
    
    # remove space
    json_users=${json_users// /}

    # search user
    user_search="\"name\":\"$cp_username\""

    if [[ $json_users =~ $user_search ]]; then
        echo "Username already exist: $cp_username"
        return 1
    fi

    return 0
}

function validate_name () {
    local name="$1"
	local regex="^[a-zA-Z ]+$"
	if ! [[ $name =~ $regex ]]; then
        echo "Invalid $2."
        return 1
	fi
    return 0
}

function validate_password () {
    local password="$1"

    # check minumum length
    local min_length=8
    if ! [[ ${#password} -ge $min_length ]]; then
        echo "The password must be at least 8 characters long"
        return 1
    fi
 
    # check is upper and lower exist
    if ! [[ "$password" =~ [a-z] && "$password" =~ [A-Z] ]]; then
        echo "The password must contain upper and lower case letters"
        return 1
    fi    

    # check is number exist
    if ! [[ "$password" =~ [0-9] ]]; then
        echo "The password must contain numbers"
        return 1
    fi

    # check is special character exist
    local special_chars="!@#$%^&*()_+[]{}|;:'\",.<>?~"
    local found=false;
    for ((i = 0; i < ${#password}; i++)); 
    do
        char="${password:i:1}"
        if [[ "$special_chars" == *"$char"* ]]; then
            found=true
            break
        fi
    done   

    if ! [[ $found ]]; then
        echo "The password must contain special characters"
        return 1
    fi        

    return 0
}

function validate_password_match () {
	if [ $1 != $2 ]; then
        echo "Passwords does not match."
        return 1
	fi
    return 0
}

function validate_email () {
    local email="$1"
    local regex="^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"

    if ! [[ $email =~ $regex ]]; then
        echo "$email: Invalid email address."
        return 1                    
    fi

    return 0
}
 
function validate_domain () {
    local domain="$1"
    local regex="^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$"

    if ! [[ $domain =~ $regex ]]; then
        echo "Invalid domain name."
        return 1
    fi
}

function validate_cp_password () {
    validate_password $cp_password || return 1
    read -sp "Re-type password for new Cyberpanel user: "$'\n' cp_password2
    validate_password_match $cp_password $cp_password2 || return 1

    return 0
}

function validate_wp_username () {
	if [[ $wp_username == "s" ]]; then
	    wp_username=cp_username
	else
        validate_username $wp_username || return 1
	fi
    return 0
}

function validate_wp_email () {
	if [[ $wp_email == "s" ]]; then
		wp_email=cp_email
	else
		validate_email $wp_email || return 1
	fi
    return 0
}

function validate_wp_password () {
    if [[ $wp_password == "s" ]]; then
        wp_password=cp_password
    else
        validate_password $wp_password || return 1
        read -sp "Re-type password for WordPress: "$'\n' wp_password2  
        validate_password_match $wp_password $wp_password2 || return 1
    fi
    return 0
}

# Get Username for Cyberpanel
valid=0
while [[ $valid == 0 ]]; do
    read -p "Enter username for new Cyberpanel user: " cp_username
    validate_cp_username && valid=1
done

# Get First Name for Cyberpanel
valid=0
while [[ $valid == 0 ]]; do
    read -p "Enter first name for new Cyberpanel user: " cp_first_name
    validate_name $cp_first_name "first name"  && valid=1
done

# Get Last Name for Cyberpanel
valid=0
while [[ $valid == 0 ]]; do
    read -p "Enter last name for new Cyberpanel user: " cp_last_name
    validate_name $cp_last_name "last name" && valid=1
done

# Get Email for Cyberpanel
valid=0
while [[ $valid == 0 ]]; do
    read -p "Enter email for new Cyberpanel user: " cp_email
    validate_email $cp_email && valid=1
done

# Get Password for Cyberpanel
valid=0
while [[ $valid == 0 ]]; do
    read -sp "Enter password for new Cyberpanel user: "$'\n' cp_password
    validate_cp_password && valid=1
done


# Get Domain Name
valid=0
while [[ $valid == 0 ]]; do
    read -p "Enter domain name: " domain_name
    validate_domain $domain_name && valid=1
done

# Get Title for WordPress
read -p "Enter WordPress Title: " wp_title

# Get Username for WordPress
valid=0
while [[ $valid == 0 ]]; do
    read -p "Enter username for WordPress (type s to use cyperpanel user username): " wp_username
    validate_wp_username && valid=1
done

# Get Email for WordPress
valid=0
while [[ $valid == 0 ]]; do
    read -p "Enter email for WordPress (type s to use cyperpanel user email): " wp_email
    validate_wp_email && valid=1
done

# Get password for WordPress
valid=0
while [[ $valid == 0 ]]; do
    read -sp "Enter password for WordPress (type s to use cyperpanel user password): "$'\n' wp_password
    validate_wp_password && valid=1
done

# generate database name based on domain nane
db_name="${domain_name//[-.]/_}_$(head /dev/urandom | tr -dc 'a-zA-Z0-9' | head -c 5)"

# generate database user based on domain nane
db_user="${domain_name//[-.]/_}_$(head /dev/urandom | tr -dc 'a-zA-Z0-9' | head -c 5)"

# generate random password for database
db_pass=$(openssl rand -base64 48 | cut -c1-$(shuf -i 20-30 -n 1))

# Create CP User
echo "Creating Cyberpanel user.."
cyberpanel createUser \
	--firstName "$cp_first_name" \
	--lastName "$cp_last_name" \
	--email $cp_email \
	--userName $cp_username \
	--password "$cp_password" \
	--websitesLimit $cp_website_limit \
	--selectedACL user \
	--securityLevel HIGH;

# Create Website
echo "Creating website.."
cyberpanel createWebsite \
	--package $cp_package \
	--owner $cp_username \
	--domainName $domain_name \
	--email $wp_email \
	--php $cp_php_version \
	--ssl $cp_ssl \
    --dkim $cp_dkim \
	--openBasedir $cp_openBasedir;

# Create Database
echo "Creating database.."
cyberpanel createDatabase \
	--databaseWebsite $domain_name \
	--dbName $db_name \
	--dbUsername $db_user \
	--dbPassword "$db_pass";

# get web vars
web_dir="/home/$domain_name/public_html"
web_user=$(ls -l $web_dir | tail -1 | cut -d ' ' -f 3)

# Download WordPress
echo "Downloading WordPress.."
sudo -u $web_user -i wp core download \
	--locale=$wp_locale \
	--path=$web_dir;

# Create config file
echo "Creating config file.."
sudo -u $web_user -i wp config create \
	--dbname=$db_name \
	--dbuser=$db_user \
	--dbpass="$db_pass" \
	--locale=$wp_locale \
	--path=$web_dir;

# Install WordPress
echo "Installing WordPress.."
sudo -u $web_user -i wp core install \
	--url="https://$domain_name" \
	--title="$wp_title" \
	--admin_user=$wp_username \
	--admin_password=$wp_password \
	--admin_email=$wp_email \
	--path=$web_dir;

echo "Apply your custom setup.."
# update options
sudo -u $web_user -i wp option update timezone_string $timezone --path=$web_dir;

# set permalink
echo "apache_modules:
    - mod_rewrite" | sudo -u $web_user -i tee wp-cli.yml
sudo -u $web_user -i wp rewrite structure '/%postname%/' --path=$web_dir
sudo -u $web_user -i wp rewrite flush --hard --path=$web_dir
sudo -u $web_user -i rm wp-cli.yml
sudo systemctl restart lsws

# Remove unnecessary plugins
sudo -u $web_user -i wp plugin delete akismet --path=$web_dir;
sudo -u $web_user -i wp plugin delete hello --path=$web_dir;

# Install necessary plugins
sudo -u $web_user -i wp plugin install wpvivid-backuprestore --activate --path=$web_dir;
sudo -u $web_user -i wp plugin install litespeed-cache --path=$web_dir;

# install theme
sudo -u $web_user -i wp theme install astra --activate --path=$web_dir;

# remove inactive themes
for theme in $(sudo -u $web_user -i wp theme list --field=name --status=inactive --path=$web_dir); do
    echo sudo -u $web_user -i wp theme delete $theme --path=$web_dir
done

echo "Done, your WordPress site is ready!"
