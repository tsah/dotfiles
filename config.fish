# ssh
export SSH_KEY_PATH="~/.ssh/rsa_id"

# Set personal aliases, overriding those provided by oh-my-zsh libs,
# plugins, and themes. Aliases can be placed here, though oh-my-zsh
# users are encouraged to define aliases within the ZSH_CUSTOM folder.
# For a full list of active aliases, run `alias`.
#
# Useful environment vars
export DTC_TSAH_IP="10.25.150.52"
export DTC_NIR_IP="10.25.150.49"
export DTC_MICHAL_IP=""
export DTC_ILIA_IP="10.25.150.55"
export DTC_NELLY_IP=""
export DTC_NAZARII_IP=""

function local-tsah
    ssh root@wsd1tsah
end

function local-savva
    ssh root@wsd1savva
end

function local-elena
    ssh root@wsd1elena 
end

function dtc-tsah
    ssh -t clfadmin@$DTC_TSAH_IP 'sudo -i' 
end

function dtc-nir
    ssh -t clfadmin@$DTC_NIR_IP 'sudo -i'
end

function dtc-michal
    ssh -t clfadmin@$DTC_MICHAL_IP 'sudo -i'
end

function dtc-ilia
    ssh -t clfadmin@$DTC_ILIA_IP 'sudo -i'
end

function dtc-nelly
    ssh -t clfadmin@$DTC_NELLY_IP 'sudo -i'
end

function dtc-nelly
    ssh -t clfadmin@$DTC_NAZARII_IP 'sudo -i'
end

function maketar
    tar zcvf 
end

function untar
    tar xvf 
end

function bigfiles
    du -a / | sort -n -r | head -n  
end

function rmall
    rm -rf * 
end

function tailf
    tail -f 
end

function gjava
    ps -ef | grep java 
end

function kjava
    pkill -9 java 
end

function glg
    git log --graph --oneline --decorate --all
end
