# Cloud CV Hosting on AWS

Name: Muhammad Mustafa | Roll no: 23L-3026 | Region: ap-southeast-2 (Sydney)

- EC2 site: http://3.24.177.98
- Lambda site: https://ffqg3nnewmygbbv53ofsmglyaa0ifbro.lambda-url.ap-southeast-2.on.aws/

## 1. Architecture

    Path A (EC2)
      Visitor --HTTP :80--> EC2 t3.micro (Apache + cron sync every 2 minutes)
                                   |  role cv-ec2-role-23l-3026: GetObject, ListBucket (site/ only)
                                   v
                            S3 bucket cv-23l-3026 (private, versioned, site/ only)
                                   ^
                                   |  role cv-lambda-role-23l-3026: GetObject (site/ only)
      Visitor --HTTPS--> Lambda function URL --> Lambda cv-func-23l-3026
    Path B (Lambda)

**EC2 path:** A visitor's browser sends an HTTP request on port 80 to the instance's public IPv4 address, where Apache serves the files from /var/www/html. A cron job runs sync-cv.sh every 2 minutes, which copies site/ from the private bucket using the instance role and replaces the placeholder with EC2 and the instance ID.

**Lambda path:** A visitor's browser sends an HTTPS request to the Lambda function URL, which invokes the function. The function reads the requested file from the private bucket using its own role and returns it, with the placeholder replaced by Lambda and the function name.

## 2. Access denied from the instance

I logged in to the instance over SSH and tried to delete and overwrite an object. Both were refused:

    delete failed: s3://cv-23l-3026/site/index.html An error occurred (AccessDenied) when calling the DeleteObject operation: User: arn:aws:sts::844280511763:assumed-role/cv-ec2-role-23l-3026/i-0abc07cf895aa89b0 is not authorized to perform: s3:DeleteObject on resource: "arn:aws:s3:::cv-23l-3026/site/index.html" because no identity-based policy allows the s3:DeleteObject action
    upload failed: ../../tmp/x to s3://cv-23l-3026/site/index.html An error occurred (AccessDenied) when calling the PutObject operation: User: arn:aws:sts::844280511763:assumed-role/cv-ec2-role-23l-3026/i-0abc07cf895aa89b0 is not authorized to perform: s3:PutObject on resource: "arn:aws:s3:::cv-23l-3026/site/index.html" because no identity-based policy allows the s3:PutObject action

## 3. Last 10 lines of /var/log/cv-sync.log

    2026-10-24T13:52:01+00:00 sync OK
    2026-10-24T13:54:02+00:00 sync OK
    2026-10-24T13:56:02+00:00 sync OK
    2026-10-24T13:58:02+00:00 sync OK
    2026-10-24T14:00:03+00:00 sync OK
    2026-10-24T14:02:01+00:00 sync OK
    2026-10-24T14:04:02+00:00 sync OK
    2026-10-24T14:06:03+00:00 sync OK
    2026-10-24T14:08:02+00:00 sync OK
    2026-10-24T14:10:02+00:00 sync OK

## 4. Written answers

**1. Why do the instance and the function use roles instead of access keys? What could go wrong if the keys were in the user data?**

A role gives the instance or the function temporary credentials that AWS issues automatically and rotates, so there is no permanent secret for me to store or protect. An access key is long-lived and works from anywhere until someone deletes it. User data is plain text that can be read from the instance metadata and the console, and my user-data.sh is in a public GitHub repository. If a key were in it, anyone who found it could use my account's permissions from their own computer until I noticed and deactivated it. Role credentials expire within hours, which limits the damage.

**2. Someone pastes the S3 address of index.html into a browser. What do they see, and which setting causes that?**

They see an XML page saying Access Denied with HTTP status 403, and my evidence file shows 403 application/xml for that address. The cause is Block Public Access, which has all four settings turned on for the bucket. A browser request carries no AWS credentials, and there is no bucket policy or ACL that grants anything to everyone, so nothing allows it.

**3. Explain in your own words the permission on the function URL that lets anyone call it. Why is that acceptable for the function but not for the bucket?**

The function URL has a resource-based policy with the principal set to * (everyone) that allows lambda:InvokeFunctionUrl when the URL's auth type is NONE, plus lambda:InvokeFunction only when the call comes through the function URL. In plain words, anyone on the internet can call the URL without an AWS login, but they cannot invoke the function any other way. This is acceptable because the function acts as a gatekeeper: its code serves only three fixed paths and returns 404 for everything else, and its role can only read site/*. A public bucket has no code in front of it, so visitors could fetch or list any object directly, including anything I upload later. So the function is public by design, while the bucket stays private and reachable only through the two roles.

**4. Compare the two paths. What do you pay for when nobody visits the site? What happens if the traffic grows a hundred times?**

With no visitors, the EC2 path still costs money because the t3.micro runs 24 hours a day, plus its disk and public IPv4 address. Lambda costs almost nothing when idle because it is billed per request and run time, leaving only tiny S3 and log storage charges. If traffic grew a hundred times, one t3.micro has fixed capacity and would slow down or fail unless I resized it or added more instances behind a load balancer, which adds cost and work. Lambda scales automatically by running more copies in parallel, within account limits, and the bill grows with the number of requests.

**5. You delete the EC2 instance. What do you lose and what do you still have?**

I would lose the running server itself: Apache, the sync script and its cron schedule, the sync log, the disk contents and the public IP address, so the EC2 address would stop working. Because it is not an Elastic IP, even a new instance would get a different address. I would still have the CV files in S3 with their versions, both IAM roles and policies, the security group, and the whole Lambda site with its URL and logs. Since user-data.sh and sync-cv.sh are in the repository, I could launch a new instance, attach the same role and have the site running again within minutes.

## 5. Repository layout

    README.md  collect-evidence.sh  evidence.txt
    site/    index.html, style.css, cv.pdf
    ec2/     user-data.sh, sync-cv.sh
    lambda/  lambda_function.py, function-url-permission.json
    iam/     trust and permission JSON of both roles

## 6. Sources and tools

I used the course material and the official AWS documentation. With my teacher's permission, I used Claude (an AI assistant made by Anthropic) to guide me through the console steps and to help draft the scripts (sync-cv.sh, user-data.sh, the Lambda function and collect-evidence.sh), the IAM policies and the draft written answers. I ran and tested everything in my own AWS account, reviewed the answers, and I can explain every part of this submission.
