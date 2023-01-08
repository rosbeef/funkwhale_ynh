#!/bin/bash

#=================================================
# COMMON VARIABLES
#=================================================

# dependencies used by the app (must be on a single line)
pkg_dependencies="curl python3-pip python3-venv git unzip libldap2-dev libsasl2-dev gettext-base zlib1g-dev libffi-dev libssl-dev \
	build-essential ffmpeg libjpeg-dev libmagic-dev libpq-dev postgresql postgresql-contrib python3-dev make \
	redis-server \
	`# add arm support` \
	zlib1g-dev libffi-dev libssl-dev"
python_version="$(python3 -V | cut -d' ' -f2 | cut -d. -f1-2)"

#=================================================
# PERSONAL HELPERS
#=================================================
install_sources() {
    # Clean venv if it was on python with an old version in case major upgrade of debian
    if [ ! -e $final_path/lib/python$python_version ]; then
        ynh_secure_remove --file=$final_path/bin
        ynh_secure_remove --file=$final_path/lib
        ynh_secure_remove --file=$final_path/lib64
        ynh_secure_remove --file=$final_path/include
        ynh_secure_remove --file=$final_path/share
        ynh_secure_remove --file=$final_path/pyvenv.cfg
    fi

    mkdir -p $final_path
    chown $app:root -R $final_path

    if [ -n "$(uname -m | grep arm)" ]
     then
        # Install rustup is not already installed
        # We need this to be able to install cryptgraphy
        export PATH="$PATH:$final_path/.cargo/bin:$final_path/.local/bin:/usr/local/sbin"
        if [ -e $final_path/.rustup ]; then
            sudo -u "$app" env PATH=$PATH rustup update
        else
            sudo -u "$app" bash -c 'curl -sSf -L https://static.rust-lang.org/rustup.sh | sh -s -- -y --default-toolchain=stable --profile=minimal'
        fi
    fi
    
    pushd $final_path
	 test -e $final_path/virtualenv/bin/python3 ||python3 -m venv $final_path/virtualenv
	source $final_path/virtualenv/bin/activate
	pip install --upgrade pip
	pip install --upgrade setuptools
	ynh_exec_warn_less pip install wheel
	# Workaround for error AttributeError: module 'lib' has no attribute 'X509_V_FLAG_CB_ISSUER_CHECK'
	ynh_replace_string --match_string="pyOpenSSL~=20.0.1" --replace_string="pyOpenSSL~=21.0.0" --target_file="$final_path/api/requirements/base.txt"
	ynh_exec_warn_less pip install -r api/requirements.txt
    popd

}

#=================================================
# EXPERIMENTAL HELPERS
#=================================================

#=================================================
#
# Redis HELPERS
#
# Point of contact : Jean-Baptiste Holcroft <jean-baptiste@holcroft.fr>
#=================================================

# get the first available redis database
#
# usage: ynh_redis_get_free_db
# | returns: the database number to use
ynh_redis_get_free_db() {
	local result max db
	result=$(redis-cli INFO keyspace)

	# get the num
	max=$(cat /etc/redis/redis.conf | grep ^databases | grep -Eow "[0-9]+")

	db=0
	# default Debian setting is 15 databases
	for i in $(seq 0 "$max")
	do
	 	if ! echo "$result" | grep -q "db$i"
	 	then
			db=$i
	 		break 1
 		fi
 		db=-1
	done

	test "$db" -eq -1 && ynh_die --message="No available Redis databases..."

	echo "$db"
}

# Create a master password and set up global settings
# Please always call this script in install and restore scripts
#
# usage: ynh_redis_remove_db database
# | arg: database - the database to erase
ynh_redis_remove_db() {
	local db=$1
	redis-cli -n "$db" flushall
}
