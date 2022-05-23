'''
ExtIP:Port
IntIP=x.x.x.z/32
PeerIP=x.x.x.y/32
IntNet=x.x.x.0
Route=0.0.0.0/0(new default) or 0.0.0.0/1,128.0.0.0/1(+default)

     Client                     Server
-------------------------------------------------
Interface.PrivateKey     -> Peer.PublicKey
Peer.PublicKey           <- Interface.PrivateKey
Peer.PresharedKey         = Peer.PresharedKey
Interface.Address(PeerIP) = Peer.AllowedIPs
Peer.Endpoint(ExtIP:Port) = Interface.ListenPort
Peer.AllowedIPs(Route)
'''
