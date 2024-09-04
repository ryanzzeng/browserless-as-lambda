const chromium = require('@sparticuz/chromium');
const puppeteer = require('puppeteer-core');
const AWS = require('aws-sdk');

const s3 = new AWS.S3();
const BUCKET_NAME = process.env.S3_BUCKET_NAME; // Set this in Lambda environment variables
const API_KEY = process.env.API_KEY; // Set this in Lambda environment variables

exports.handler = async (event) => {
    let browser = null;
    try {
        console.log('Received event:', JSON.stringify(event, null, 2));

        // Check API Key
        const providedApiKey = event.headers['x-api-key'] || event.headers['X-Api-Key'];
        if (providedApiKey !== API_KEY) {
            return {
                statusCode: 401,
                body: JSON.stringify({ error: 'Unauthorized: Invalid API Key' })
            };
        }

        let html;
        console.log(event.html)
        if (event.body) {
            try {
                let body = JSON.parse(event.body);
                html = body.html;
            } catch (error) {
                console.error('Error parsing body:', error);
                return {
                    statusCode: 400,
                    body: JSON.stringify({ error: 'Bad Request: Invalid JSON body' })
                };
            }
        } else {
            throw new Error('No body found in the event');
        }

        console.log('Launching browser');
        browser = await puppeteer.launch({
            args: chromium.args,
            defaultViewport: chromium.defaultViewport,
            executablePath: await chromium.executablePath(),
            headless: chromium.headless,
        });

        console.log('Creating new page');
        const page = await browser.newPage();
        await page.setContent(html);

        console.time('PDF Generation');
        console.log('Generating PDF');
        const pdf = await page.pdf({ format: 'A4' , omitBackground: false, printBackground: true, margin: {
            bottom: 64,
            top: 64
        }});
        console.timeEnd('PDF Generation');

        console.log('PDF generated successfully');

        // Upload PDF to S3
        const key = `pdfs/${Date.now()}.pdf`;
        await s3.putObject({
            Bucket: BUCKET_NAME,
            Key: key,
            Body: pdf,
            ContentType: 'application/pdf'
        }).promise();

        console.log(`PDF uploaded to S3: ${BUCKET_NAME}/${key}`);

        // Generate signed URL
        const signedUrl = s3.getSignedUrl('getObject', {
            Bucket: BUCKET_NAME,
            Key: key,
            Expires: 3600 // URL expires in 1 hour
        });

        return {
            statusCode: 200,
            headers: {
                "Content-Type": "application/json"
            },
            body: JSON.stringify({
                message: 'PDF generated and uploaded to S3',
                downloadUrl: signedUrl
            })
        };
    } catch (error) {
        console.error('Error:', error);
        return {
            statusCode: 500,
            headers: {
                "Content-Type": "application/json"
            },
            body: JSON.stringify({ error: error.message || 'Failed to generate PDF' })
        };
    } finally {
        if (browser !== null) {
            await browser.close();
        }
    }
};