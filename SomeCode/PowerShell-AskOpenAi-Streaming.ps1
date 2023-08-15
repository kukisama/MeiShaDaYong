<#
.SYNOPSIS
    这个脚本设计用于与OpenAI API交互，提出问题并获得回答。优点是流式输出 
    MS zhangpengliang

.DESCRIPTION
    脚本包含三个函数：
    1. Invoke-OpenAIStream: 处理API的响应流。
    2. Invoke-OpenAIRequest: 向API发送POST请求。
    3. Ask-OpenAI: 主函数，准备问题并发送给API。

.PARAMETER Endpoint
    OpenAI API的端点URL。

.PARAMETER SubscriptionKey
    OpenAI API的订阅密钥。

.PARAMETER RoleSystem
    对话中系统的角色。

.PARAMETER Question
    要问OpenAI API的问题。

.PARAMETER Tokens
    生成响应中的最大令牌数量。默认为4000。

.PARAMETER PrintQuestion
    在发送前打印问题的开关参数。

.EXAMPLE
    $endpoint = "https://xxxx.aaa-api.net/openai/bb/99/chat/completions?api-version=abc"
    $subscriptionKey = "这里放你的key"
    $roleSystem = "你的名字叫小芳，你可以帮助大家推荐各种美食，你是一个60岁的老奶奶，注意要在合适的地方换行，因为如果不换行，提问者会不太容易理解"
    $question = '大兄弟你给我推荐点北京好吃的吧，越详细越好，要推荐多多的美食'
    $tokens = 4000

    Ask-OpenAI -Endpoint $endpoint -SubscriptionKey $subscriptionKey -RoleSystem $roleSystem -Question $question -Tokens $tokens -PrintQuestion

.NOTES
    这个脚本需要System.Net.Http.HttpResponseMessage类。

#>
function Invoke-OpenAIStream {
    param (
        [System.Net.Http.HttpResponseMessage]$Response
    )

    $streamTask = $Response.Content.ReadAsStreamAsync()
    $stream = $streamTask.Result
    $reader = New-Object System.IO.StreamReader($stream)

    while ($true) {
        $line = $reader.ReadLine()
        if ($line -eq $null) {
            break
        }
        if ($line -eq 'data: [DONE]') {
            break
        }
        $abc = (($line -replace '^data: ', '') | ConvertFrom-Json).choices.delta.content
        Write-Host $abc -NoNewline
    }
}

function Invoke-OpenAIRequest {
    param (
        [string]$Url,
        [string]$SubscriptionKey,
        [PSCustomObject]$Body
    )

    $header = @{
        "api-key" =  $SubscriptionKey
        "Content-Type" = "application/json; charset=utf-8"
    }
    
    $client = New-Object System.Net.Http.HttpClient
    $request = [System.Net.Http.HttpRequestMessage]::new()
    $request.Method = "POST"
    $request.RequestUri = $Url
    $request.Content = [System.Net.Http.StringContent]::new(($Body | ConvertTo-Json), [System.Text.Encoding]::UTF8)
    $request.Content.Headers.Clear()

    foreach($key in $header.Keys) {
        $lowerKey = $key.ToLower()  
        $values = [string[]]@($header[$lowerKey])
        $request.Content.Headers.Add($lowerKey, $values) 
    }

    $task = $client.SendAsync($request, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead)
    return $task.Result
}

function Ask-OpenAI {
    param (
        [string]$Endpoint,
        [string]$SubscriptionKey,
        [string]$RoleSystem,
        [string]$Question,
        [int]$Tokens = 4000,
        [switch]$PrintQuestion
    )

    if ($PrintQuestion) {
        Write-Host -ForegroundColor Green $Question
    }

    $messages = @()
    if ($RoleSystem) {
        $messages += @{
            role    = "system"
            content =  $RoleSystem
        }
    }

    $messages += @{
        role    = "user"
        content =   $Question
    }

    $body = @{
        messages = $messages
        temperature = 0.5
        top_p    = 0.95
        frequency_penalty = 0
        presence_penalty = 0
        max_tokens = $Tokens
        stop	 = $null
        stream  = $true
    }

    $response = Invoke-OpenAIRequest -Url $Endpoint -SubscriptionKey $SubscriptionKey -Body $body
    Invoke-OpenAIStream -Response $response
}

# 示例用法,终结点放你的Azure OpenAI的终结点
    $endpoint = "https://xxxx.aaa-api.net/openai/bb/99/chat/completions?api-version=abc"
    $subscriptionKey = "这里放你的key"
    $roleSystem = "你的名字叫小芳，你可以帮助大家推荐各种美食，你是一个60岁的老奶奶，注意要在合适的地方换行，因为如果不换行，提问者会不太容易理解"
    $question = '大兄弟你给我推荐点北京好吃的吧，越详细越好，要推荐多多的美食'
    $tokens = 4000

Ask-OpenAI -Endpoint $endpoint -SubscriptionKey $subscriptionKey -RoleSystem $roleSystem -Question $question -Tokens $tokens -PrintQuestion
