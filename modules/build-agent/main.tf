# WARNING: this sub-module is still unimplemented, not to prototype stage


// https://registry.terraform.io/providers/Mastercard/restapi/latest
/*
   Use the Teamcity RESTAPI to determine if there is an agent with a
   matching name. Upon success a 200 code should be returned with JSON
   and a member called 'id'.
*/
data "http" "agent_lookup" {
  url = "${var.server_url}/app/rest/agents?locator=name:${var.name}"
  method = "GET"

  request_headers = {
    Authorization = "Bearer ${var.admin_token}"
    Accept        = "application/json"
  }
}

locals {
  existing_agent_id   = data.http.agent_lookup.status_code == 200 ? try(jsondecode(data.http.agent_lookup.response_body).agent[0].id, null) : 0
}

/*
  Attempt to register a *new* build agent with the given name.

  This is off piste, and not documented or supported by JetBrains. This is way
  off the concept of 'develop with pleasure'.

  This should get a XML response of the form:
  ```
     <Response><data class="AgentRegistrationDetails"><agentId>74</agentId><token>xxxx</token><newName>nnn</newName></data></Response>
  ```

*/
data "http" "agent_register" {
  count = local.existing_agent_id == 0 ? 1 : 0

  url    = "${var.server_url}/app/rest/agents/id:${local.existing_agent_id}/token"
  method = "POST"

  request_headers = {
    Authorization = "Bearer ${var.admin_token}"
    Accept        = "application/xml"
    Content-Type = "application/xml; charset=UTF-8"
  }
  request_body =<<EOT
  <?xml version="1.0" encoding="UTF-8"?>
  <agentDetails agentName="${var.name}" agentPort="9090" authToken="" osName="Linux, version 6.6.95-flatcar">
      <alternativeAddresses />
      <availableRunners />
      <availableVcs />
      <buildParameters />
      <configParameters />
  </agentDetails>
EOT
}

locals {
  pattern = "(?is)^\\s*<Response>.*?<data\\s+class=[\"']AgentRegistrationDetails[\"']>.*?<agentId>\\s*([0-9]+)\\s*</agentId>.*?<token>\\s*([a-f0-9]+)\\s*</token>.*?</data>.*?</Response>\\s*$"
  captures = (local.existing_agent_id == 0 && data.http.agent_register[0].status_code == 200) ? regex(local.pattern, data.http.agent_register[0].response_body) : []

  new_agent_id   = length(local.captures) >= 1 ? tonumber(local.captures[0]) : 0
  new_token   = length(local.captures) >= 2 ? local.captures[1] : ""
}

locals {
    agent_id = local.existing_agent_id != 0 ? local.existing_agent_id : local.new_agent_id
}


data "http" "agent_authorisation" {
  count = (length(local.new_token) > 0) ? 0 : 0
  url    = "${var.server_url}/app/rest/agents/id:${local.agent_id}/authorizedInfo"
  method = "POST"

  request_headers = {
    Authorization = "Bearer ${var.admin_token}"
    Content-Type  = "application/json"
  }

  request_body = jsonencode({
    "comment" : {
      "text" : "Provisioned by Terraform"
    },
    "status" : true
  })

  lifecycle {
    postcondition {
      condition     = self.status_code == 200
      error_message = "Request to authorise agent '${var.name}' (${local.agent_id}) failed with status ${self.status_code}"
    }
  }
}

/**
    Create a new agent auth token. The JetBrains Terraform provider doesn't appear to
    support this resource, so provision it via a http request to the REST API.

    see:
      - https://www.jetbrains.com/help/teamcity/rest/manage-agents.html
      - https://registry.terraform.io/providers/JetBrains/teamcity/latest
      - https://registry.terraform.io/providers/hashicorp/http/latest/docs/data-sources/http
 */
data "http" "agent_token" {
  count = 0 # length(local.new_token)
  url    = "${var.server_url}/app/rest/agentAuthTokens"
  method = "POST"

  request_headers = {
    Authorization = "Bearer ${var.admin_token}"
    Accept        = "application/json"
    Content-Type  = "application/json"
  }

  # Optional: give the token a label for identification
  request_body = jsonencode({
    name = var.name
  })

  lifecycle {
    postcondition {
      condition     = self.status_code == 200
      error_message = "Request to POST ${self.url} failed with status ${self.status_code}"
    }
  }
}


/*
http://teamcity.lucidsolutions.co.nz/app/agents/protocols

"GET /app/agents/protocols HTTP/1.1"  200 37 "-" "TeamCity Agent 2025.07.1" "-" rt=0.004 ua="10.20.20.2:8111" us="200" ut="0.004" ul="37" cs=-
"GET /app/rest/server/nodes HTTP/1.1"  200 151 "-" "TeamCity Agent 2025.07.1" "-" rt=0.076 ua="10.20.20.2:8111" us="200" ut="0.076" ul="151" cs=-
"POST /app/agents/v1/register HTTP/1.1"  200 169 "-" "TeamCity Agent 2025.07.1" "-" rt=0.044 ua="10.20.20.2:8111" us="200" ut="0.042" ul="169" cs=-
"GET /app/agents/v1/commands/next HTTP/1.1"  200 0 "-" "TeamCity Agent 2025.07.1" "-" rt=0.010 ua="10.20.20.2:8111" us="200" ut="0.010" ul="0" cs=-
"POST /app/agents/v1/commands/result HTTP/1.1"  200 54 "-" "TeamCity Agent 2025.07.1" "-" rt=0.007 ua="10.20.20.2:8111" us="200" ut="0.007" ul="54" cs=-
"GET /update/teamcity-agent.xml HTTP/1.1"  200 8738 "-" "TeamCity Agent 2025.07.1" "-" rt=0.005 ua="10.20.20.2:8111" us="200" ut="0.005" ul="8738" cs=-
"GET /app/agents/v1/commands/next HTTP/1.1"  200 58 "-" "TeamCity Agent 2025.07.1" "-" rt=0.010 ua="10.20.20.2:8111" us="200" ut="0.010" ul="58" cs=-
"GET /update/plugins/agentSystemInfo.zip HTTP/1.1"  200 5965 "-" "TeamCity Agent 2025.07.1" "-" rt=0.005 ua="10.20.20.2:8111" us="200" ut="0.005" ul="5965" cs=-
"GET /update/plugins/amazonEC2.zip HTTP/1.1"  200 34609 "-" "TeamCity Agent 2025.07.1" "-" rt=0.035 ua="10.20.20.2:8111" us="200" ut="0.035" ul="34609" cs=-
"POST /RPC2 HTTP/1.1"  200 132 "-" "TeamCity Agent" "-" rt=0.011 ua="10.20.20.2:8111" us="200" ut="0.011" ul="132" cs=-



tshark host 10.20.20.2 and port 8111 -O http

Transmission Control Protocol, Src Port: 46238 (46238), Dst Port: 8111 (8111), Seq: 1, Ack: 1, Len: 4426
Hypertext Transfer Protocol
    POST /app/agents/v1/register HTTP/1.1\r\n
        [Expert Info (Chat/Sequence): POST /app/agents/v1/register HTTP/1.1\r\n]
            [Message: POST /app/agents/v1/register HTTP/1.1\r\n]
            [Severity level: Chat]
            [Group: Sequence]
        Request Method: POST
        Request URI: /app/agents/v1/register
        Request Version: HTTP/1.1
    Host: teamcity.lucidsolutions.co.nz\r\n
    X-Real-IP: ::ffff:10.20.20.4\r\n
    X-Forwarded-For: ::ffff:10.20.20.4\r\n
    X-Forwarded-Host: teamcity.lucidsolutions.co.nz\r\n
    X-Forwarded-Proto: https\r\n
    Content-Length: 4042\r\n
        [Content length: 4042]
    User-Agent: TeamCity Agent 2025.07.1\r\n
    Cookie: $Version=0; X-TeamCity-Node-Id-Cookie=MAIN_SERVER\r\n
    Content-Type: application/xml; charset=UTF-8\r\n
    \r\n
    [Full request URI: http://teamcity.lucidsolutions.co.nz/app/agents/v1/register]
    [HTTP request 1/1]
eXtensible Markup Language

    HTTP/1.1 200 \r\n
        [Expert Info (Chat/Sequence): HTTP/1.1 200 \r\n]
            [Message: HTTP/1.1 200 \r\n]
            [Severity level: Chat]
            [Group: Sequence]
        Request Version: HTTP/1.1
        Status Code: 200
    TeamCity-Node-Id: MAIN_SERVER\r\n
    TeamCity-AgentSessionId: 60:2d8b88bbb0dbb6f613004ee4f9c09238\r\n
    Content-Length: 174\r\n
        [Content length: 174]
    Date: Mon, 18 Aug 2025 01:55:51 GMT\r\n
    \r\n
    [HTTP response 1/1]
    [Time since request: 0.023454284 seconds]
    [Request in frame: 27]
    Data (174 bytes)

0000  3c 52 65 73 70 6f 6e 73 65 3e 3c 64 61 74 61 20   <Response><data
0010  63 6c 61 73 73 3d 22 41 67 65 6e 74 52 65 67 69   class="AgentRegi
0020  73 74 72 61 74 69 6f 6e 44 65 74 61 69 6c 73 22   strationDetails"
0030  3e 3c 61 67 65 6e 74 49 64 3e 36 30 3c 2f 61 67   ><agentId>60</ag
0040  65 6e 74 49 64 3e 3c 74 6f 6b 65 6e 3e 32 64 38   entId><token>2d8
0050  62 38 38 62 62 62 30 64 62 62 36 66 36 31 33 30   b88bbb0dbb6f6130
0060  30 34 65 65 34 66 39 63 30 39 32 33 38 3c 2f 74   04ee4f9c09238</t
0070  6f 6b 65 6e 3e 3c 6e 65 77 4e 61 6d 65 3e 61 61   oken><newName>aa
0080  46 6c 61 74 63 61 72 20 4c 69 6e 75 78 20 31 30   Flatcar Linux 10
0090  2d 34 3c 2f 6e 65 77 4e 61 6d 65 3e 3c 2f 64 61   -4</newName></da
00a0  74 61 3e 3c 2f 52 65 73 70 6f 6e 73 65 3e         ta></Response>
        Data: 3c526573706f6e73653e3c6461746120636c6173733d2241...
        [Length: 174]




<Response>
  <data class="AgentRegistrationDetails">
    <agentId>60</agentId>
    <token>2d8b88bbb0dbb6f613004ee4f9c09238</token>
    <newName>aaFlatcar Linux 10 -4</newName>
  </data>
</Response>















0000  c6 db 42 b0 e7 a4 00 aa 10 14 07 02 08 00 45 00   ..B...........E.
0010  11 7e f2 d5 40 00 40 06 07 79 0a 14 07 02 0a 14   .~..@.@..y......
0020  14 02 d5 f0 1f af 85 fb 04 6f 8e 06 f1 9d 80 18   .........o......
0030  01 a4 40 9c 00 00 01 01 08 0a 8f 5a f6 be 42 0d   ..@........Z..B.
0040  ab fe 50 4f 53 54 20 2f 61 70 70 2f 61 67 65 6e   ..POST /app/agen
0050  74 73 2f 76 31 2f 72 65 67 69 73 74 65 72 20 48   ts/v1/register H
0060  54 54 50 2f 31 2e 31 0d 0a 48 6f 73 74 3a 20 74   TTP/1.1..Host: t
0070  65 61 6d 63 69 74 79 2e 6c 75 63 69 64 73 6f 6c   eamcity.lucidsol
0080  75 74 69 6f 6e 73 2e 63 6f 2e 6e 7a 0d 0a 58 2d   utions.co.nz..X-
0090  52 65 61 6c 2d 49 50 3a 20 3a 3a 66 66 66 66 3a   Real-IP: ::ffff:
00a0  31 30 2e 32 30 2e 32 30 2e 34 0d 0a 58 2d 46 6f   10.20.20.4..X-Fo
00b0  72 77 61 72 64 65 64 2d 46 6f 72 3a 20 3a 3a 66   rwarded-For: ::f
00c0  66 66 66 3a 31 30 2e 32 30 2e 32 30 2e 34 0d 0a   fff:10.20.20.4..
00d0  58 2d 46 6f 72 77 61 72 64 65 64 2d 48 6f 73 74   X-Forwarded-Host
00e0  3a 20 74 65 61 6d 63 69 74 79 2e 6c 75 63 69 64   : teamcity.lucid
00f0  73 6f 6c 75 74 69 6f 6e 73 2e 63 6f 2e 6e 7a 0d   solutions.co.nz.
0100  0a 58 2d 46 6f 72 77 61 72 64 65 64 2d 50 72 6f   .X-Forwarded-Pro
0110  74 6f 3a 20 68 74 74 70 73 0d 0a 43 6f 6e 74 65   to: https..Conte
0120  6e 74 2d 4c 65 6e 67 74 68 3a 20 34 30 34 32 0d   nt-Length: 4042.
0130  0a 55 73 65 72 2d 41 67 65 6e 74 3a 20 54 65 61   .User-Agent: Tea
0140  6d 43 69 74 79 20 41 67 65 6e 74 20 32 30 32 35   mCity Agent 2025
0150  2e 30 37 2e 31 0d 0a 43 6f 6f 6b 69 65 3a 20 24   .07.1..Cookie: $
0160  56 65 72 73 69 6f 6e 3d 30 3b 20 58 2d 54 65 61   Version=0; X-Tea
0170  6d 43 69 74 79 2d 4e 6f 64 65 2d 49 64 2d 43 6f   mCity-Node-Id-Co
0180  6f 6b 69 65 3d 4d 41 49 4e 5f 53 45 52 56 45 52   okie=MAIN_SERVER
0190  0d 0a 43 6f 6e 74 65 6e 74 2d 54 79 70 65 3a 20   ..Content-Type:
01a0  61 70 70 6c 69 63 61 74 69 6f 6e 2f 78 6d 6c 3b   application/xml;
01b0  20 63 68 61 72 73 65 74 3d 55 54 46 2d 38 0d 0a    charset=UTF-8..
01c0  0d 0a 3c 3f 78 6d 6c 20 76 65 72 73 69 6f 6e 3d   ..<?xml version=
01d0  22 31 2e 30 22 20 65 6e 63 6f 64 69 6e 67 3d 22   "1.0" encoding="
01e0  55 54 46 2d 38 22 3f 3e 0a 3c 61 67 65 6e 74 44   UTF-8"?>.<agentD
01f0  65 74 61 69 6c 73 20 61 67 65 6e 74 4e 61 6d 65   etails agentName
0200  3d 22 61 61 46 6c 61 74 63 61 72 20 4c 69 6e 75   ="aaFlatcar Linu
0210  78 20 31 30 22 20 61 67 65 6e 74 50 6f 72 74 3d   x 10" agentPort=
0220  22 39 30 39 30 22 20 61 75 74 68 54 6f 6b 65 6e   "9090" authToken
0230  3d 22 22 20 70 69 6e 67 43 6f 64 65 3d 22 32 59   ="" pingCode="2Y
0240  6d 62 6e 55 48 33 44 54 55 56 51 33 68 75 66 6a   mbnUH3DTUVQ3hufj
0250  66 4a 47 4b 7a 6b 70 4c 64 7a 6d 57 73 63 22 20   fJGKzkpLdzmWsc"
0260  6f 73 4e 61 6d 65 3d 22 4c 69 6e 75 78 2c 20 76   osName="Linux, v
0270  65 72 73 69 6f 6e 20 36 2e 36 2e 39 35 2d 66 6c   ersion 6.6.95-fl
0280  61 74 63 61 72 22 3e 0a 20 20 3c 61 6c 74 65 72   atcar">.  <alter
0290  6e 61 74 69 76 65 41 64 64 72 65 73 73 65 73 20   nativeAddresses
02a0  2f 3e 0a 20 20 3c 61 76 61 69 6c 61 62 6c 65 52   />.  <availableR
02b0  75 6e 6e 65 72 73 20 2f 3e 0a 20 20 3c 61 76 61   unners />.  <ava
02c0  69 6c 61 62 6c 65 56 63 73 20 2f 3e 0a 20 20 3c   ilableVcs />.  <
02d0  62 75 69 6c 64 50 61 72 61 6d 65 74 65 72 73 3e   buildParameters>
02e0  0a 20 20 20 20 3c 70 61 72 61 6d 20 6e 61 6d 65   .    <param name
02f0  3d 22 65 6e 76 2e 41 47 45 4e 54 5f 4e 41 4d 45   ="env.AGENT_NAME
0300  22 20 76 61 6c 75 65 3d 22 61 61 46 6c 61 74 63   " value="aaFlatc
0310  61 72 20 4c 69 6e 75 78 20 31 30 22 20 2f 3e 0a   ar Linux 10" />.
0320  20 20 20 20 3c 70 61 72 61 6d 20 6e 61 6d 65 3d       <param name=
0330  22 65 6e 76 2e 41 47 45 4e 54 5f 54 4f 4b 45 4e   "env.AGENT_TOKEN
0340  22 20 76 61 6c 75 65 3d 22 22 20 2f 3e 0a 20 20   " value="" />.
0350  20 20 3c 70 61 72 61 6d 20 6e 61 6d 65 3d 22 65     <param name="e
0360  6e 76 2e 41 53 50 4e 45 54 43 4f 52 45 5f 55 52   nv.ASPNETCORE_UR
0370  4c 53 22 20 76 61 6c 75 65 3d 22 68 74 74 70 3a   LS" value="http:
0380  2f 2f 2b 3a 38 30 22 20 2f 3e 0a 20 20 20 20 3c   //+:80" />.    <
0390  70 61 72 61 6d 20 6e 61 6d 65 3d 22 65 6e 76 2e   param name="env.
03a0  43 4f 4e 46 49 47 5f 46 49 4c 45 22 20 76 61 6c   CONFIG_FILE" val
03b0  75 65 3d 22 2f 64 61 74 61 2f 74 65 61 6d 63 69   ue="/data/teamci
03c0  74 79 5f 61 67 65 6e 74 2f 63 6f 6e 66 2f 62 75   ty_agent/conf/bu
03d0  69 6c 64 41 67 65 6e 74 2e 70 72 6f 70 65 72 74   ildAgent.propert
03e0  69 65 73 22 20 2f 3e 0a 20 20 20 20 3c 70 61 72   ies" />.    <par
03f0  61 6d 20 6e 61 6d 65 3d 22 65 6e 76 2e 44 45 42   am name="env.DEB
0400  49 41 4e 5f 46 52 4f 4e 54 45 4e 44 22 20 76 61   IAN_FRONTEND" va
0410  6c 75 65 3d 22 6e 6f 6e 69 6e 74 65 72 61 63 74   lue="noninteract
0420  69 76 65 22 20 2f 3e 0a 20 20 20 20 3c 70 61 72   ive" />.    <par
0430  61 6d 20 6e 61 6d 65 3d 22 65 6e 76 2e 44 4f 54   am name="env.DOT
0440  4e 45 54 5f 43 4c 49 5f 54 45 4c 45 4d 45 54 52   NET_CLI_TELEMETR
0450  59 5f 4f 50 54 4f 55 54 22 20 76 61 6c 75 65 3d   Y_OPTOUT" value=
0460  22 74 72 75 65 22 20 2f 3e 0a 20 20 20 20 3c 70   "true" />.    <p
0470  61 72 61 6d 20 6e 61 6d 65 3d 22 65 6e 76 2e 44   aram name="env.D
0480  4f 54 4e 45 54 5f 52 55 4e 4e 49 4e 47 5f 49 4e   OTNET_RUNNING_IN
0490  5f 43 4f 4e 54 41 49 4e 45 52 22 20 76 61 6c 75   _CONTAINER" valu
04a0  65 3d 22 74 72 75 65 22 20 2f 3e 0a 20 20 20 20   e="true" />.
04b0  3c 70 61 72 61 6d 20 6e 61 6d 65 3d 22 65 6e 76   <param name="env
04c0  2e 44 4f 54 4e 45 54 5f 53 44 4b 5f 56 45 52 53   .DOTNET_SDK_VERS
04d0  49 4f 4e 22 20 76 61 6c 75 65 3d 22 22 20 2f 3e   ION" value="" />
04e0  0a 20 20 20 20 3c 70 61 72 61 6d 20 6e 61 6d 65   .    <param name
04f0  3d 22 65 6e 76 2e 44 4f 54 4e 45 54 5f 53 4b 49   ="env.DOTNET_SKI
0500  50 5f 46 49 52 53 54 5f 54 49 4d 45 5f 45 58 50   P_FIRST_TIME_EXP
0510  45 52 49 45 4e 43 45 22 20 76 61 6c 75 65 3d 22   ERIENCE" value="
0520  74 72 75 65 22 20 2f 3e 0a 20 20 20 20 3c 70 61   true" />.    <pa
0530  72 61 6d 20 6e 61 6d 65 3d 22 65 6e 76 2e 44 4f   ram name="env.DO
0540  54 4e 45 54 5f 55 53 45 5f 50 4f 4c 4c 49 4e 47   TNET_USE_POLLING
0550  5f 46 49 4c 45 5f 57 41 54 43 48 45 52 22 20 76   _FILE_WATCHER" v
0560  61 6c 75 65 3d 22 74 72 75 65 22 20 2f 3e 0a 20   alue="true" />.
0570  20 20 20 3c 70 61 72 61 6d 20 6e 61 6d 65 3d 22      <param name="
0580  65 6e 76 2e 47 49 54 5f 53 53 48 5f 56 41 52 49   env.GIT_SSH_VARI
0590  41 4e 54 22 20 76 61 6c 75 65 3d 22 73 73 68 22   ANT" value="ssh"
05a0  20 2f 3e 0a 20 20 20 20 3c 70 61 72 61 6d 20 6e    />.    <param n
05b0  61 6d 65 3d 22 65 6e 76 2e 48 4f 4d 45 22 20 76   ame="env.HOME" v
05c0  61 6c 75 65 3d 22 2f 68 6f 6d 65 2f 62 75 69 6c   alue="/home/buil
05d0  64 61 67 65 6e 74 22 20 2f 3e 0a 20 20 20 20 3c   dagent" />.    <
05e0  70 61 72 61 6d 20 6e 61 6d 65 3d 22 65 6e 76 2e   param name="env.
05f0  48 4f 53 54 4e 41 4d 45 22 20 76 61 6c 75 65 3d   HOSTNAME" value=
0600  22 31 2e 6b 68 61 6b 69 2e 6c 75 63 69 64 73 6f   "1.khaki.lucidso
0610  6c 75 74 69 6f 6e 73 2e 63 6f 2e 6e 7a 22 20 2f   lutions.co.nz" /
0620  3e 0a 20 20 20 20 3c 70 61 72 61 6d 20 6e 61 6d   >.    <param nam
0630  65 3d 22 65 6e 76 2e 4a 41 56 41 5f 48 4f 4d 45   e="env.JAVA_HOME
0640  22 20 76 61 6c 75 65 3d 22 2f 6f 70 74 2f 6a 61   " value="/opt/ja
0650  76 61 2f 6f 70 65 6e 6a 64 6b 22 20 2f 3e 0a 20   va/openjdk" />.
0660  20 20 20 3c 70 61 72 61 6d 20 6e 61 6d 65 3d 22      <param name="
0670  65 6e 76 2e 4a 44 4b 5f 48 4f 4d 45 22 20 76 61   env.JDK_HOME" va
0680  6c 75 65 3d 22 2f 6f 70 74 2f 6a 61 76 61 2f 6f   lue="/opt/java/o
0690  70 65 6e 6a 64 6b 22 20 2f 3e 0a 20 20 20 20 3c   penjdk" />.    <
06a0  70 61 72 61 6d 20 6e 61 6d 65 3d 22 65 6e 76 2e   param name="env.
06b0  4c 41 4e 47 22 20 76 61 6c 75 65 3d 22 43 2e 55   LANG" value="C.U
06c0  54 46 2d 38 22 20 2f 3e 0a 20 20 20 20 3c 70 61   TF-8" />.    <pa
06d0  72 61 6d 20 6e 61 6d 65 3d 22 65 6e 76 2e 4c 41   ram name="env.LA
06e0  4e 47 55 41 47 45 22 20 76 61 6c 75 65 3d 22 65   NGUAGE" value="e
06f0  6e 5f 55 53 3a 65 6e 22 20 2f 3e 0a 20 20 20 20   n_US:en" />.
0700  3c 70 61 72 61 6d 20 6e 61 6d 65 3d 22 65 6e 76   <param name="env
0710  2e 4c 43 5f 41 4c 4c 22 20 76 61 6c 75 65 3d 22   .LC_ALL" value="
0720  65 6e 5f 55 53 2e 55 54 46 2d 38 22 20 2f 3e 0a   en_US.UTF-8" />.
0730  20 20 20 20 3c 70 61 72 61 6d 20 6e 61 6d 65 3d       <param name=
0740  22 65 6e 76 2e 4e 55 47 45 54 5f 58 4d 4c 44 4f   "env.NUGET_XMLDO
0750  43 5f 4d 4f 44 45 22 20 76 61 6c 75 65 3d 22 73   C_MODE" value="s
0760  6b 69 70 22 20 2f 3e 0a 20 20 20 20 3c 70 61 72   kip" />.    <par
0770  61 6d 20 6e 61 6d 65 3d 22 65 6e 76 2e 4f 4c 44   am name="env.OLD
0780  50 57 44 22 20 76 61 6c 75 65 3d 22 2f 22 20 2f   PWD" value="/" /
0790  3e 0a 20 20 20 20 3c 70 61 72 61 6d 20 6e 61 6d   >.    <param nam
07a0  65 3d 22 65 6e 76 2e 50 41 54 48 22 20 76 61 6c   e="env.PATH" val
07b0  75 65 3d 22 2f 6f 70 74 2f 6a 61 76 61 2f 6f 70   ue="/opt/java/op
07c0  65 6e 6a 64 6b 2f 62 69 6e 3a 2f 75 73 72 2f 6c   enjdk/bin:/usr/l
07d0  6f 63 61 6c 2f 73 62 69 6e 3a 2f 75 73 72 2f 6c   ocal/sbin:/usr/l
07e0  6f 63 61 6c 2f 62 69 6e 3a 2f 75 73 72 2f 73 62   ocal/bin:/usr/sb
07f0  69 6e 3a 2f 75 73 72 2f 62 69 6e 3a 2f 73 62 69   in:/usr/bin:/sbi
0800  6e 3a 2f 62 69 6e 22 20 2f 3e 0a 20 20 20 20 3c   n:/bin" />.    <
0810  70 61 72 61 6d 20 6e 61 6d 65 3d 22 65 6e 76 2e   param name="env.
0820  50 57 44 22 20 76 61 6c 75 65 3d 22 2f 6f 70 74   PWD" value="/opt
0830  2f 62 75 69 6c 64 61 67 65 6e 74 2f 62 69 6e 22   /buildagent/bin"
0840  20 2f 3e 0a 20 20 20 20 3c 70 61 72 61 6d 20 6e    />.    <param n
0850  61 6d 65 3d 22 65 6e 76 2e 53 45 52 56 45 52 5f   ame="env.SERVER_
0860  55 52 4c 22 20 76 61 6c 75 65 3d 22 68 74 74 70   URL" value="http
0870  73 3a 2f 2f 74 65 61 6d 63 69 74 79 2e 6c 75 63   s://teamcity.luc
0880  69 64 73 6f 6c 75 74 69 6f 6e 73 2e 63 6f 2e 6e   idsolutions.co.n
0890  7a 22 20 2f 3e 0a 20 20 20 20 3c 70 61 72 61 6d   z" />.    <param
08a0  20 6e 61 6d 65 3d 22 65 6e 76 2e 53 48 4c 56 4c    name="env.SHLVL
08b0  22 20 76 61 6c 75 65 3d 22 31 22 20 2f 3e 0a 20   " value="1" />.
08c0  20 20 20 3c 70 61 72 61 6d 20 6e 61 6d 65 3d 22      <param name="
08d0  65 6e 76 2e 54 45 41 4d 43 49 54 59 5f 44 4f 43   env.TEAMCITY_DOC
08e0  4b 45 52 5f 4e 45 54 57 4f 52 4b 22 20 76 61 6c   KER_NETWORK" val
08f0  75 65 3d 22 68 6f 73 74 22 20 2f 3e 0a 20 20 20   ue="host" />.
0900  20 3c 70 61 72 61 6d 20 6e 61 6d 65 3d 22 65 6e    <param name="en
0910  76 2e 54 5a 22 20 76 61 6c 75 65 3d 22 50 61 63   v.TZ" value="Pac
0920  69 66 69 63 2f 41 75 63 6b 6c 61 6e 64 22 20 2f   ific/Auckland" /
0930  3e 0a 20 20 20 20 3c 70 61 72 61 6d 20 6e 61 6d   >.    <param nam
0940  65 3d 22 65 6e 76 2e 5f 22 20 76 61 6c 75 65 3d   e="env._" value=
0950  22 2f 75 73 72 2f 62 69 6e 2f 6e 6f 68 75 70 22   "/usr/bin/nohup"
0960  20 2f 3e 0a 20 20 20 20 3c 70 61 72 61 6d 20 6e    />.    <param n
0970  61 6d 65 3d 22 73 79 73 74 65 6d 2e 61 67 65 6e   ame="system.agen
0980  74 2e 68 6f 6d 65 2e 64 69 72 22 20 76 61 6c 75   t.home.dir" valu
0990  65 3d 22 2f 6f 70 74 2f 62 75 69 6c 64 61 67 65   e="/opt/buildage
09a0  6e 74 22 20 2f 3e 0a 20 20 20 20 3c 70 61 72 61   nt" />.    <para
09b0  6d 20 6e 61 6d 65 3d 22 73 79 73 74 65 6d 2e 61   m name="system.a
09c0  67 65 6e 74 2e 6e 61 6d 65 22 20 76 61 6c 75 65   gent.name" value
09d0  3d 22 61 61 46 6c 61 74 63 61 72 20 4c 69 6e 75   ="aaFlatcar Linu
09e0  78 20 31 30 22 20 2f 3e 0a 20 20 20 20 3c 70 61   x 10" />.    <pa
09f0  72 61 6d 20 6e 61 6d 65 3d 22 73 79 73 74 65 6d   ram name="system
0a00  2e 61 67 65 6e 74 2e 77 6f 72 6b 2e 64 69 72 22   .agent.work.dir"
0a10  20 76 61 6c 75 65 3d 22 2f 6f 70 74 2f 62 75 69    value="/opt/bui
0a20  6c 64 61 67 65 6e 74 2f 77 6f 72 6b 22 20 2f 3e   ldagent/work" />
0a30  0a 20 20 20 20 3c 70 61 72 61 6d 20 6e 61 6d 65   .    <param name
0a40  3d 22 73 79 73 74 65 6d 2e 74 65 61 6d 63 69 74   ="system.teamcit
0a50  79 2e 62 75 69 6c 64 2e 74 65 6d 70 44 69 72 22   y.build.tempDir"
0a60  20 76 61 6c 75 65 3d 22 2f 6f 70 74 2f 62 75 69    value="/opt/bui
0a70  6c 64 61 67 65 6e 74 2f 74 65 6d 70 2f 62 75 69   ldagent/temp/bui
0a80  6c 64 54 6d 70 22 20 2f 3e 0a 20 20 3c 2f 62 75   ldTmp" />.  </bu
0a90  69 6c 64 50 61 72 61 6d 65 74 65 72 73 3e 0a 20   ildParameters>.
0aa0  20 3c 63 6f 6e 66 69 67 50 61 72 61 6d 65 74 65    <configParamete
0ab0  72 73 3e 0a 20 20 20 20 3c 70 61 72 61 6d 20 6e   rs>.    <param n
0ac0  61 6d 65 3d 22 74 65 61 6d 63 69 74 79 2e 61 67   ame="teamcity.ag
0ad0  65 6e 74 2e 68 6f 6d 65 2e 64 69 72 22 20 76 61   ent.home.dir" va
0ae0  6c 75 65 3d 22 2f 6f 70 74 2f 62 75 69 6c 64 61   lue="/opt/builda
0af0  67 65 6e 74 22 20 2f 3e 0a 20 20 20 20 3c 70 61   gent" />.    <pa
0b00  72 61 6d 20 6e 61 6d 65 3d 22 74 65 61 6d 63 69   ram name="teamci
0b10  74 79 2e 61 67 65 6e 74 2e 68 6f 73 74 6e 61 6d   ty.agent.hostnam
0b20  65 22 20 76 61 6c 75 65 3d 22 31 2e 6b 68 61 6b   e" value="1.khak
0b30  69 2e 6c 75 63 69 64 73 6f 6c 75 74 69 6f 6e 73   i.lucidsolutions
0b40  2e 63 6f 2e 6e 7a 22 20 2f 3e 0a 20 20 20 20 3c   .co.nz" />.    <
0b50  70 61 72 61 6d 20 6e 61 6d 65 3d 22 74 65 61 6d   param name="team
0b60  63 69 74 79 2e 61 67 65 6e 74 2e 6a 76 6d 2e 66   city.agent.jvm.f
0b70  69 6c 65 2e 65 6e 63 6f 64 69 6e 67 22 20 76 61   ile.encoding" va
0b80  6c 75 65 3d 22 55 54 46 2d 38 22 20 2f 3e 0a 20   lue="UTF-8" />.
0b90  20 20 20 3c 70 61 72 61 6d 20 6e 61 6d 65 3d 22      <param name="
0ba0  74 65 61 6d 63 69 74 79 2e 61 67 65 6e 74 2e 6a   teamcity.agent.j
0bb0  76 6d 2e 66 69 6c 65 2e 73 65 70 61 72 61 74 6f   vm.file.separato
0bc0  72 22 20 76 61 6c 75 65 3d 22 2f 22 20 2f 3e 0a   r" value="/" />.
0bd0  20 20 20 20 3c 70 61 72 61 6d 20 6e 61 6d 65 3d       <param name=
0be0  22 74 65 61 6d 63 69 74 79 2e 61 67 65 6e 74 2e   "teamcity.agent.
0bf0  6a 76 6d 2e 6a 61 76 61 2e 68 6f 6d 65 22 20 76   jvm.java.home" v
0c00  61 6c 75 65 3d 22 2f 6f 70 74 2f 6a 61 76 61 2f   alue="/opt/java/
0c10  6f 70 65 6e 6a 64 6b 22 20 2f 3e 0a 20 20 20 20   openjdk" />.
0c20  3c 70 61 72 61 6d 20 6e 61 6d 65 3d 22 74 65 61   <param name="tea
0c30  6d 63 69 74 79 2e 61 67 65 6e 74 2e 6a 76 6d 2e   mcity.agent.jvm.
0c40  6f 73 2e 61 72 63 68 22 20 76 61 6c 75 65 3d 22   os.arch" value="
0c50  61 6d 64 36 34 22 20 2f 3e 0a 20 20 20 20 3c 70   amd64" />.    <p
0c60  61 72 61 6d 20 6e 61 6d 65 3d 22 74 65 61 6d 63   aram name="teamc
0c70  69 74 79 2e 61 67 65 6e 74 2e 6a 76 6d 2e 6f 73   ity.agent.jvm.os
0c80  2e 6e 61 6d 65 22 20 76 61 6c 75 65 3d 22 4c 69   .name" value="Li
0c90  6e 75 78 22 20 2f 3e 0a 20 20 20 20 3c 70 61 72   nux" />.    <par
0ca0  61 6d 20 6e 61 6d 65 3d 22 74 65 61 6d 63 69 74   am name="teamcit
0cb0  79 2e 61 67 65 6e 74 2e 6a 76 6d 2e 6f 73 2e 76   y.agent.jvm.os.v
0cc0  65 72 73 69 6f 6e 22 20 76 61 6c 75 65 3d 22 36   ersion" value="6
0cd0  2e 36 2e 39 35 2d 66 6c 61 74 63 61 72 22 20 2f   .6.95-flatcar" /
0ce0  3e 0a 20 20 20 20 3c 70 61 72 61 6d 20 6e 61 6d   >.    <param nam
0cf0  65 3d 22 74 65 61 6d 63 69 74 79 2e 61 67 65 6e   e="teamcity.agen
0d00  74 2e 6a 76 6d 2e 70 61 74 68 2e 73 65 70 61 72   t.jvm.path.separ
0d10  61 74 6f 72 22 20 76 61 6c 75 65 3d 22 3a 22 20   ator" value=":"
0d20  2f 3e 0a 20 20 20 20 3c 70 61 72 61 6d 20 6e 61   />.    <param na
0d30  6d 65 3d 22 74 65 61 6d 63 69 74 79 2e 61 67 65   me="teamcity.age
0d40  6e 74 2e 6a 76 6d 2e 73 70 65 63 69 66 69 63 61   nt.jvm.specifica
0d50  74 69 6f 6e 22 20 76 61 6c 75 65 3d 22 32 31 22   tion" value="21"
0d60  20 2f 3e 0a 20 20 20 20 3c 70 61 72 61 6d 20 6e    />.    <param n
0d70  61 6d 65 3d 22 74 65 61 6d 63 69 74 79 2e 61 67   ame="teamcity.ag
0d80  65 6e 74 2e 6a 76 6d 2e 75 73 65 72 2e 63 6f 75   ent.jvm.user.cou
0d90  6e 74 72 79 22 20 76 61 6c 75 65 3d 22 55 53 22   ntry" value="US"
0da0  20 2f 3e 0a 20 20 20 20 3c 70 61 72 61 6d 20 6e    />.    <param n
0db0  61 6d 65 3d 22 74 65 61 6d 63 69 74 79 2e 61 67   ame="teamcity.ag
0dc0  65 6e 74 2e 6a 76 6d 2e 75 73 65 72 2e 68 6f 6d   ent.jvm.user.hom
0dd0  65 22 20 76 61 6c 75 65 3d 22 2f 68 6f 6d 65 2f   e" value="/home/
0de0  62 75 69 6c 64 61 67 65 6e 74 22 20 2f 3e 0a 20   buildagent" />.
0df0  20 20 20 3c 70 61 72 61 6d 20 6e 61 6d 65 3d 22      <param name="
0e00  74 65 61 6d 63 69 74 79 2e 61 67 65 6e 74 2e 6a   teamcity.agent.j
0e10  76 6d 2e 75 73 65 72 2e 6c 61 6e 67 75 61 67 65   vm.user.language
0e20  22 20 76 61 6c 75 65 3d 22 65 6e 22 20 2f 3e 0a   " value="en" />.
0e30  20 20 20 20 3c 70 61 72 61 6d 20 6e 61 6d 65 3d       <param name=
0e40  22 74 65 61 6d 63 69 74 79 2e 61 67 65 6e 74 2e   "teamcity.agent.
0e50  6a 76 6d 2e 75 73 65 72 2e 6e 61 6d 65 22 20 76   jvm.user.name" v
0e60  61 6c 75 65 3d 22 62 75 69 6c 64 61 67 65 6e 74   alue="buildagent
0e70  22 20 2f 3e 0a 20 20 20 20 3c 70 61 72 61 6d 20   " />.    <param
0e80  6e 61 6d 65 3d 22 74 65 61 6d 63 69 74 79 2e 61   name="teamcity.a
0e90  67 65 6e 74 2e 6a 76 6d 2e 75 73 65 72 2e 74 69   gent.jvm.user.ti
0ea0  6d 65 7a 6f 6e 65 22 20 76 61 6c 75 65 3d 22 50   mezone" value="P
0eb0  61 63 69 66 69 63 2f 41 75 63 6b 6c 61 6e 64 22   acific/Auckland"
0ec0  20 2f 3e 0a 20 20 20 20 3c 70 61 72 61 6d 20 6e    />.    <param n
0ed0  61 6d 65 3d 22 74 65 61 6d 63 69 74 79 2e 61 67   ame="teamcity.ag
0ee0  65 6e 74 2e 6a 76 6d 2e 76 65 6e 64 6f 72 22 20   ent.jvm.vendor"
0ef0  76 61 6c 75 65 3d 22 41 6d 61 7a 6f 6e 2e 63 6f   value="Amazon.co
0f00  6d 20 49 6e 63 2e 22 20 2f 3e 0a 20 20 20 20 3c   m Inc." />.    <
0f10  70 61 72 61 6d 20 6e 61 6d 65 3d 22 74 65 61 6d   param name="team
0f20  63 69 74 79 2e 61 67 65 6e 74 2e 6a 76 6d 2e 76   city.agent.jvm.v
0f30  65 72 73 69 6f 6e 22 20 76 61 6c 75 65 3d 22 32   ersion" value="2
0f40  31 2e 30 2e 36 22 20 2f 3e 0a 20 20 20 20 3c 70   1.0.6" />.    <p
0f50  61 72 61 6d 20 6e 61 6d 65 3d 22 74 65 61 6d 63   aram name="teamc
0f60  69 74 79 2e 61 67 65 6e 74 2e 6c 61 75 6e 63 68   ity.agent.launch
0f70  65 72 2e 76 65 72 73 69 6f 6e 22 20 76 61 6c 75   er.version" valu
0f80  65 3d 22 32 30 32 35 2e 30 37 2d 31 39 37 33 32   e="2025.07-19732
0f90  35 22 20 2f 3e 0a 20 20 20 20 3c 70 61 72 61 6d   5" />.    <param
0fa0  20 6e 61 6d 65 3d 22 74 65 61 6d 63 69 74 79 2e    name="teamcity.
0fb0  61 67 65 6e 74 2e 6e 61 6d 65 22 20 76 61 6c 75   agent.name" valu
0fc0  65 3d 22 61 61 46 6c 61 74 63 61 72 20 4c 69 6e   e="aaFlatcar Lin
0fd0  75 78 20 31 30 22 20 2f 3e 0a 20 20 20 20 3c 70   ux 10" />.    <p
0fe0  61 72 61 6d 20 6e 61 6d 65 3d 22 74 65 61 6d 63   aram name="teamc
0ff0  69 74 79 2e 61 67 65 6e 74 2e 6f 73 2e 61 72 63   ity.agent.os.arc
1000  68 2e 62 69 74 73 22 20 76 61 6c 75 65 3d 22 36   h.bits" value="6
1010  34 22 20 2f 3e 0a 20 20 20 20 3c 70 61 72 61 6d   4" />.    <param
1020  20 6e 61 6d 65 3d 22 74 65 61 6d 63 69 74 79 2e    name="teamcity.
1030  61 67 65 6e 74 2e 6f 77 6e 50 6f 72 74 22 20 76   agent.ownPort" v
1040  61 6c 75 65 3d 22 39 30 39 30 22 20 2f 3e 0a 20   alue="9090" />.
1050  20 20 20 3c 70 61 72 61 6d 20 6e 61 6d 65 3d 22      <param name="
1060  74 65 61 6d 63 69 74 79 2e 61 67 65 6e 74 2e 74   teamcity.agent.t
1070  6f 6f 6c 73 2e 64 69 72 22 20 76 61 6c 75 65 3d   ools.dir" value=
1080  22 2f 6f 70 74 2f 62 75 69 6c 64 61 67 65 6e 74   "/opt/buildagent
1090  2f 74 6f 6f 6c 73 22 20 2f 3e 0a 20 20 20 20 3c   /tools" />.    <
10a0  70 61 72 61 6d 20 6e 61 6d 65 3d 22 74 65 61 6d   param name="team
10b0  63 69 74 79 2e 61 67 65 6e 74 2e 77 6f 72 6b 2e   city.agent.work.
10c0  64 69 72 22 20 76 61 6c 75 65 3d 22 2f 6f 70 74   dir" value="/opt
10d0  2f 62 75 69 6c 64 61 67 65 6e 74 2f 77 6f 72 6b   /buildagent/work
10e0  22 20 2f 3e 0a 20 20 20 20 3c 70 61 72 61 6d 20   " />.    <param
10f0  6e 61 6d 65 3d 22 74 65 61 6d 63 69 74 79 2e 73   name="teamcity.s
1100  65 72 76 65 72 55 72 6c 22 20 76 61 6c 75 65 3d   erverUrl" value=
1110  22 68 74 74 70 73 3a 2f 2f 74 65 61 6d 63 69 74   "https://teamcit
1120  79 2e 6c 75 63 69 64 73 6f 6c 75 74 69 6f 6e 73   y.lucidsolutions
1130  2e 63 6f 2e 6e 7a 22 20 2f 3e 0a 20 20 3c 2f 63   .co.nz" />.  </c
1140  6f 6e 66 69 67 50 61 72 61 6d 65 74 65 72 73 3e   onfigParameters>
1150  0a 20 20 3c 76 65 72 73 69 6f 6e 20 61 67 65 6e   .  <version agen
1160  74 3d 22 31 39 37 33 32 35 22 20 70 6c 75 67 69   t="197325" plugi
1170  6e 73 3d 22 4e 41 22 20 2f 3e 0a 3c 2f 61 67 65   ns="NA" />.</age
1180  6e 74 44 65 74 61 69 6c 73 3e 0a 0a               ntDetails>..


<?xml version="1.0" encoding="UTF-8"?>
<agentDetails agentName="aaFlatcar Linux 10" agentPort="9090" authToken="" pingCode="2Ym...LdzmWsc" osName="Linux, version 6.6.95-flatcar">
  <alternativeAddresses />
  <availableRunners />
  <availableVcs />
  <buildParameters>
    <param name="env.AGENT_NAME" value="aaFlatcar Linux 10" />
    <param name="env.AGENT_TOKEN" value="" />
    <param name="env.ASPNETCORE_URLS" value="http://+:80" />
    <param name="env.CONFIG_FILE" value="/data/teamcity_agent/conf/buildAgent.properties" />
    <param name="env.DEBIAN_FRONTEND" value="noninteractive" />
    <param name="env.DOTNET_CLI_TELEMETRY_OPTOUT" value="true" />
    <param name="env.DOTNET_RUNNING_IN_CONTAINER" value="true" />
    <param name="env.DOTNET_SDK_VERSION" value="" />
    <param name="env.DOTNET_SKIP_FIRST_TIME_EXPERIENCE" value="true" />
    <param name="env.DOTNET_USE_POLLING_FILE_WATCHER" value="true" />
    <param name="env.GIT_SSH_VARIANT" value="ssh" />
    <param name="env.HOME" value="/home/buildagent" />
    <param name="env.HOSTNAME" value="1.khaki.lucidsolutions.co.nz" />
    <param name="env.JAVA_HOME" value="/opt/java/openjdk" />
    <param name="env.JDK_HOME" value="/opt/java/openjdk" />
    <param name="env.LANG" value="C.UTF-8" />
    <param name="env.LANGUAGE" value="en_US:en" />
    <param name="env.LC_ALL" value="en_US.UTF-8" />
    <param name="env.NUGET_XMLDOC_MODE" value="skip" />
    <param name="env.OLDPWD" value="/" />
    <param name="env.PATH" value="/opt/java/openjdk/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" />
    <param name="env.PWD" value="/opt/buildagent/bin" />
    <param name="env.SERVER_URL" value="https://teamcity.lucidsolutions.co.nz" />
    <param name="env.SHLVL" value="1" />
    <param name="env.TEAMCITY_DOCKER_NETWORK" value="host" />
    <param name="env.TZ" value="Pacific/Auckland" />
    <param name="env._" value="/usr/bin/nohup" />
    <param name="system.agent.home.dir" value="/opt/buildagent" />
    <param name="system.agent.name" value="aaFlatcar Linux 10" />
    <param name="system.agent.work.dir" value="/opt/buildagent/work" />
    <param name="system.teamcity.build.tempDir" value="/opt/buildagent/temp/buildTmp" />
  </buildParameters>
  <configParameters>
    <param name="teamcity.agent.home.dir" value="/opt/buildagent" />
    <param name="teamcity.agent.hostname" value="1.khaki.lucidsolutions.co.nz" />
    <param name="teamcity.agent.jvm.file.encoding" value="UTF-8" />
    <param name="teamcity.agent.jvm.file.separator" value="/" />
    <param name="teamcity.agent.jvm.java.home" value="/opt/java/openjdk" />
    <param name="teamcity.agent.jvm.os.arch" value="amd64" />
    <param name="teamcity.agent.jvm.os.name" value="Linux" />
    <param name="teamcity.agent.jvm.os.version" value="6.6.95-flatcar" />
    <param name="teamcity.agent.jvm.path.separator" value=":" />
    <param name="teamcity.agent.jvm.specification" value="21" />
    <param name="teamcity.agent.jvm.user.country" value="US" />
    <param name="teamcity.agent.jvm.user.home" value="/home/buildagent" />
    <param name="teamcity.agent.jvm.user.language" value="en" />
    <param name="teamcity.agent.jvm.user.name" value="buildagent" />
    <param name="teamcity.agent.jvm.user.timezone" value="Pacific/Auckland" />
    <param name="teamcity.agent.jvm.vendor" value="Amazon.com Inc." />
    <param name="teamcity.agent.jvm.version" value="21.0.6" />
    <param name="teamcity.agent.launcher.version" value="2025.07-197325" />
    <param name="teamcity.agent.name" value="aaFlatcar Linux 10" />
    <param name="teamcity.agent.os.arch.bits" value="64" />
    <param name="teamcity.agent.ownPort" value="9090" />
    <param name="teamcity.agent.tools.dir" value="/opt/buildagent/tools" />
    <param name="teamcity.agent.work.dir" value="/opt/buildagent/work" />
    <param name="teamcity.serverUrl" value="https://teamcity.lucidsolutions.co.nz" />
  </configParameters>
  <version agent="197325" plugins="NA" />
</agentDetails>


curl -X POST "https://teamcity.lucidsolutions.co.nz:443/app/agents/v1/register" \
  -H "Content-Type: application/xml; charset=UTF-8" \
  -H "Accept: application/json;q=1.0, application/xml;q=0.5" \
  -H "Authorization: Bearer xxx" \
  -d '<?xml version="1.0" encoding="UTF-8"?>
<agentDetails agentName="Flatcar Linux 12" agentPort="9090" authToken="" osName="Linux, version 6.6.95-flatcar">
  <alternativeAddresses />
  <availableRunners />
  <availableVcs />
  <buildParameters />
  <configParameters />
</agentDetails>'

 */