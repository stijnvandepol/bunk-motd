#!/bin/bash

cat << 'EOF'
                                                                    
  ██████╗ ██╗   ██╗███╗   ██╗██╗  ██╗                             
  ██╔══██╗██║   ██║████╗  ██║██║ ██╔╝                             
  ██████╔╝██║   ██║██╔██╗ ██║█████╔╝                              
  ██╔══██╗██║   ██║██║╚██╗██║██╔═██╗                              
  ██████╔╝╚██████╔╝██║ ╚████║██║  ██╗                             
  ╚═════╝  ╚═════╝ ╚═╝  ╚═══╝╚═╝  ╚═╝                            
                                                                    
  ██╗  ██╗ ██████╗ ███████╗████████╗██╗███╗   ██╗ ██████╗        
  ██║  ██║██╔═══██╗██╔════╝╚══██╔══╝██║████╗  ██║██╔════╝        
  ███████║██║   ██║███████╗   ██║   ██║██╔██╗ ██║██║  ███╗       
  ██╔══██║██║   ██║╚════██║   ██║   ██║██║╚██╗██║██║   ██║       
  ██║  ██║╚██████╔╝███████║   ██║   ██║██║ ╚████║╚██████╔╝       
  ╚═╝  ╚═╝ ╚═════╝ ╚══════╝   ╚═╝   ╚═╝╚═╝  ╚═══╝ ╚═════╝       
                                                                    
  ══════════════════════════════════════════════════════════════   
  ⚡  Professional Hosting Infrastructure                          
  🔒  Unauthorized access is strictly prohibited                   
  📧  support@bunkhosting.nl                                       
  ══════════════════════════════════════════════════════════════   
EOF

echo "  🖥️  Hostname:    $(hostname)"
echo "  🐧  OS:          $(lsb_release -ds)"
echo "  ⏰  Uptime:      $(uptime -p)"
echo "  📦  Kernel:      $(uname -r)"
echo "  🌐  IP:          $(hostname -I | awk '{print $1}')"
echo "  💾  Disk:        $(df -h / | awk 'NR==2{print $3"/"$2" ("$5" used)"}')"
echo "  🧠  RAM:         $(free -h | awk 'NR==2{print $3"/"$2}')"
echo "  📊  Load:        $(uptime | awk -F'load average:' '{print $2}')"
echo ""
echo "  ⚠️   $(date '+%Y-%m-%d %H:%M:%S') - All sessions are logged"
echo ""