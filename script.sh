#!/bin/bash

                                ## SCRIPT ##

                  ## Creado por Paco Diz Ureña | 2ºASIR ##

###################################################

### DEFINICIÓN DE VARIABLES GENERALES ###

dirRaiz=$(cd $(dirname "${BASH_SOURCE[0]}") >/dev/null && pwd)

###################################################

###################################################

### DEFINICIÓN DE FUNCIONES ###

#Comprobar si somos root
function f_root {
        if [ $UID != 0 ]
        then
          echo "Usuario sin privilegios.................................OK"
          return 0
        else
          echo "Este script no puede ejecutarse como Super Usuario"
          exit
        fi
        }


###################################################

# Comprobamos si el usuario que ejecuta el script no es ROOT.

echo -e "\n"
f_root


# Nos movemos al directorio del script

cd $dirRaiz


#------------------------------------------------------------------------------


# Creación de imagen nueva maquina1.qcow2
nombreVM="maquina1"

echo -e "\n+----------------------------------------------------------------------+\n"
echo "Creando imagen..."
qemu-img create -b bullseye-base.qcow2 -f qcow2 $nombreVM.qcow2 5G &> /dev/null
echo "Imagen creada.................................OK"

sleep 2

## Redimensión de sistema de ficheros

echo "Redimensionando sistema de ficheros..."
cp $nombreVM.qcow2 new$nombreVM.qcow2 &> /dev/null

sleep 2

virt-resize --expand /dev/sda1 $nombreVM.qcow2 new$nombreVM.qcow2 &> /dev/null

sleep 2

rm -f $nombreVM.qcow2 && mv new$nombreVM.qcow2 $nombreVM.qcow2 &> /dev/null
echo "+- Sistema de ficheros redimensionado con éxito -+"

echo -e "\n+----------------------------------------------------------------------+\n"


#------------------------------------------------------------------------------


# Creación de red intra 

echo "<network>
  <name>intra</name>
  <bridge name='virbr10'/>
  <forward/>
  <ip address='10.10.20.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='10.10.20.10' end='10.10.20.254'/>
    </dhcp>
  </ip>
</network>" > intra.xml


## Definimos la nueva red

virsh -c qemu:///system net-define intra.xml &> /dev/null
echo "+- Red Intra definida con éxito -+"

## Iniciamos la nueva red y la ponemos para que se autoarranque al inicio del host.

virsh -c qemu:///system net-start intra &> /dev/null
virsh -c qemu:///system net-autostart intra &> /dev/null
echo "+- Red Intra configurada con éxito -+"

## Elminamos el fichero .xml que creamos en el directorio actual.

rm intra.xml
echo -e "\n+----------------------------------------------------------------------+\n"


#------------------------------------------------------------------------------


# Creación de nueva máquina

echo "Creando máquina virtual..."
virt-install --connect qemu:///system \
			 --virt-type kvm \
			 --name $nombreVM \
			 --os-variant debian10 \
			 --disk path=$nombreVM.qcow2 \
       --import \
			 --memory 1024 \
			 --vcpus 1 \
       --network network=intra \
       --noautoconsole &> /dev/null



sleep 40

echo "Maquina creada.................................OK"

## Apagando maquina
virsh -c qemu:///system shutdown $nombreVM &> /dev/null
echo "Apagando maquina..."

sleep 6

virsh -c qemu:///system start $nombreVM &> /dev/null
echo "Encendiendo maquina..."

sleep 15


## Inicio automático de la máquina virtual

virsh -c qemu:///system autostart $nombreVM &> /dev/null
echo "+- Inicio automático configurado -+"


## Modificación del nombre de la máquina
ipVM=$(virsh -c qemu:///system domifaddr $nombreVM | grep -oE "([0-9]{1,3}[\.]){3}[0-9]{1,3}" | head -n 1)

sleep 2

echo "Modificando hostname..."
ssh -i id_ecdsa debian@$ipVM -o "StrictHostKeyChecking no" "sudo chmod 746 /etc/hostname" &> /dev/null

sleep 1

ssh -i id_ecdsa debian@$ipVM "sudo echo '$nombreVM' > /etc/hostname" &> /dev/null

sleep 1

ssh -i id_ecdsa debian@$ipVM "sudo chmod 740 /etc/hostname" &> /dev/null

sleep 1

echo "+- Hostname cambiado a $nombreVM -+"
echo -e "\n+----------------------------------------------------------------------+\n"


#------------------------------------------------------------------------------


# Creación del volumen de 1GB adicional

echo "Creando nuevo volumen..."
virsh -c qemu:///system vol-create-as default vol1.raw --format raw 1G &> /dev/null
echo "Volumen creado.................................OK"

sleep 1
echo -e "\n+----------------------------------------------------------------------+\n"


#------------------------------------------------------------------------------


# Conectar el volumen vol1.raw a la máquina

echo "Conectando nuevo volumen a $nombreVM..."
virsh -c qemu:///system attach-disk $nombreVM /var/lib/libvirt/images/vol1.raw vdb --driver=qemu --type disk --subdriver raw --persistent &> /dev/null
echo "Volumen conectado.................................OK"


## Reiniciando maquina

echo "Reiniciando maquina..."
virsh -c qemu:///system shutdown $nombreVM &> /dev/null
sleep 10
virsh -c qemu:///system start $nombreVM &> /dev/null
sleep 20


## Formatear nuevo volumen

echo "Formateando vol1.raw..."
ssh -i id_ecdsa debian@$ipVM "sudo mkfs.xfs -f /dev/vdb" &> /dev/null

## Lo montamos en /var/www/html

echo "Motando el dispositivo..."
ssh -i id_ecdsa debian@$ipVM "sudo chmod 746 /etc/fstab" &> /dev/null
ssh -i id_ecdsa debian@$ipVM "sudo echo '/dev/vdb  /var/www/html xfs  defaults  0  0' >> /etc/fstab"
ssh -i id_ecdsa debian@$ipVM "sudo chmod 740 /etc/fstab" &> /dev/null

sleep 1

ssh -i id_ecdsa debian@$ipVM "sudo mount -a" &> /dev/null
echo "Dispositivo montado.................................OK"
echo -e "\n+----------------------------------------------------------------------+\n"


#------------------------------------------------------------------------------


# Instalación de apache2

echo "Instalando servidor web..."
ssh -i id_ecdsa debian@$ipVM "sudo apt update && sudo apt install -y apache2" &> /dev/null

sleep 15
echo "Servidor web instalado.................................OK"

## Crear index.html en /var/www/html/

echo "Creando fichero index.html..."
ssh -i id_ecdsa debian@$ipVM "sudo echo 'BIENVENIDOS A LA PAGINA WEB' > index.html"
ssh -i id_ecdsa debian@$ipVM "sudo rm -f /var/www/htmml/index.html"
ssh -i id_ecdsa debian@$ipVM "sudo chmod 746 index.html && sudo mv index.html /var/www/html/" &> /dev/null
ssh -i id_ecdsa debian@$ipVM "sudo chown -R www-data:www-data /var/www/html" &> /dev/null
echo "index.html creado.................................OK"
echo -e "\n+----------------------------------------------------------------------+\n"

sleep 2


#------------------------------------------------------------------------------


# Mostrar IP y pausa del script

echo "Dirección IP obtenida: $ipVM"
echo "-----------------------"
echo "Acceso web: http://$ipVM"
read -p "Pulsa cualquier tecla para continuar"
echo -e "\n+----------------------------------------------------------------------+\n"


#------------------------------------------------------------------------------


# Instalacion LXC y crear contenedor

echo "Instalando paquete lxc..."
ssh -i id_ecdsa debian@$ipVM "sudo apt update && sudo apt install -y lxc" &> /dev/null

sleep 10

echo "Creando contenedor..."
ssh -i id_ecdsa debian@$ipVM "sudo lxc-create -n container1 -t debian -- -r bullseye" &> /dev/null

sleep 30

echo "Contenedor creado.................................OK"
echo -e "\n+----------------------------------------------------------------------+\n"


#------------------------------------------------------------------------------


# Añadir una nueva interfaz puente a la máquina (br0)

## Apagar maquina

echo "Apagando máquina..."
virsh -c qemu:///system shutdown $nombreVM &> /dev/null
sleep 10

## Añadir br0

echo "Añadiendo interfaz br0..."
virsh -c qemu:///system attach-interface maquina1 bridge br0 --model virtio --config --persistent &> /dev/null
echo "Interfaz br0.................................OK"


## Iniciando maquina

echo "Iniciando máquina..."
virsh -c qemu:///system start $nombreVM &> /dev/null
sleep 20


## Añadiendo entrada a /etc/network/interfaces de la maquina virtual

echo "Configurando br0..."
ssh -i id_ecdsa debian@$ipVM "sudo chmod 746 /etc/network/interfaces" &> /dev/null
ssh -i id_ecdsa debian@$ipVM "sudo echo 'auto enp8s0 
iface enp8s0 inet dhcp' >> /etc/network/interfaces"
ssh -i id_ecdsa debian@$ipVM "sudo chmod 740 /etc/network/interfaces" &> /dev/null
ssh -i id_ecdsa debian@$ipVM "sudo echo 'BIENVENIDOS A LA PAGINA WEB' > index.html"
ssh -i id_ecdsa debian@$ipVM "sudo rm -f /var/www/htmml/index.html"
ssh -i id_ecdsa debian@$ipVM "sudo chmod 746 index.html && sudo mv index.html /var/www/html/" &> /dev/null

## Levantar tarjeta br0

echo "Iniciando br0 en $nombreVM..."
ssh -i id_ecdsa debian@$ipVM "sudo ifup enp8s0" &> /dev/null

sleep 15

echo "Interfaz br0 configurada.................................OK"
echo -e "\n+----------------------------------------------------------------------+\n"


#------------------------------------------------------------------------------


# Mostrar IP de br0

ipbr0=$(ssh -i id_ecdsa debian@$ipVM "ip a | egrep enp8s0 | grep -oE '([0-9]{1,3}[\.]){3}[0-9]{1,3}' | head -n 1")

echo "IP br0: $ipbr0"
echo "-----------------------"
echo "Podemos ver la página web también desde esta dirección: http://$ipbr0"
read -p "Pulsa cualquier tecla para continuar"
echo -e "\n+----------------------------------------------------------------------+\n"


#------------------------------------------------------------------------------


# Apagamos la maquina, aumentamos la RAM a 2GiB y la iniciamos de nuevo

## Apagado de maquina

echo "Apagando máquina..."
virsh -c qemu:///system shutdown $nombreVM &> /dev/null
sleep 10


## Modificando la RAM

echo "Cambiando memoria RAM a 2GiB"
virt-xml -c qemu:///system  $nombreVM --edit --memory memory=2048,currentMemory=2048 &> /dev/null
echo "Memoria RAM cambiada.................................OK"


## Iniciando maquina

echo "Iniciando máquina..."
virsh -c qemu:///system start $nombreVM &> /dev/null

sleep 20
echo -e "\n+----------------------------------------------------------------------+\n"


#------------------------------------------------------------------------------


# Creacion de Snapshot de la maquina virtual

echo "Creando instantánea1 de $nombreVM..."
virsh -c qemu:///system shutdown $nombreVM &> /dev/null

sleep 10

virsh -c qemu:///system snapshot-create-as $nombreVM --name Instantánea1 --description "Instantánea1-$nombreVM" --disk-only --atomic &> /dev/null
echo "Instantánea creada.................................OK"

echo -e "\n+----------------------------------------------------------------------+\n"
echo "Fin Script"
echo -e "\n+----------------------------------------------------------------------+\n"


