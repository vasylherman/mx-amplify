#!/usr/bin/env node
'use strict'

// Amplify post-build: posts the custom-domain preview URL to the GitHub PR (via the RoboDefenseAI
// GitHub App) and to the linked Jira issue. Runs on Node (present on the Amplify build image);
// openssl/curl are not guaranteed there.

const crypto = require('crypto')
const { execSync } = require('child_process')

const env = process.env
const GITHUB_APP_ID = 4254870
const CUSTOM_DOMAIN = env.CUSTOM_DOMAIN
const APP_BASE_PATH = env.APP_BASE_PATH || ''

const fail = (msg) => {
  console.error(msg)
  process.exit(1)
}

const githubApi = async (url, opts = {}) => {
  const res = await fetch(url, {
    ...opts,
    headers: {
      Accept: 'application/vnd.github+json',
      'User-Agent': 'robodefenseai-amplify',
      ...(opts.headers || {}),
    },
  })
  const text = await res.text()
  if (!res.ok) throw new Error(`${opts.method || 'GET'} ${url} -> ${res.status}: ${text}`)
  return text ? JSON.parse(text) : {}
}

// Resolve owner/repo. Prefer GITHUB_REPOSITORY, then Amplify's default AWS_CLONE_URL, then the git remote.
const resolveRepo = () => {
  if (env.GITHUB_REPOSITORY) return env.GITHUB_REPOSITORY
  let url = env.AWS_CLONE_URL || ''
  if (!url) {
    try {
      url = execSync('git config --get remote.origin.url', { encoding: 'utf8' }).trim()
    } catch {
      /* no remote available */
    }
  }
  const match = url.match(/github\.com[:/]+(.+?)(?:\.git)?$/)
  return match ? match[1] : ''
}

const buildJwt = () => {
  const encoded = (env.ORG_ROBODEFENSEAI_PRIVATE_KEY || '').trim()
  if (!encoded) fail('ORG_ROBODEFENSEAI_PRIVATE_KEY is not set')
  // The secret holds the base64-encoded PEM (single line, so Amplify can't mangle its newlines).
  const privateKey = Buffer.from(encoded, 'base64').toString('utf8')
  if (!privateKey.includes('-----BEGIN')) {
    fail('ORG_ROBODEFENSEAI_PRIVATE_KEY did not base64-decode to a PEM private key.')
  }

  const b64url = (input) =>
    Buffer.from(input).toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')

  const now = Math.floor(Date.now() / 1000)
  const header = b64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }))
  const payload = b64url(JSON.stringify({ iat: now - 60, exp: now + 540, iss: GITHUB_APP_ID }))
  const signingInput = `${header}.${payload}`
  const signature = b64url(crypto.createSign('RSA-SHA256').update(signingInput).sign(privateKey))
  return `${signingInput}.${signature}`
}

const postGithubComment = async () => {
  const prNumber = env.AWS_PULL_REQUEST_ID
  if (!prNumber) {
    console.warn('AWS_PULL_REQUEST_ID is not set. Skipping GitHub PR comment.')
    return
  }

  const previewUrl = `https://pr-${prNumber}.${CUSTOM_DOMAIN}/${APP_BASE_PATH}`
  console.log(`Posting custom-domain preview URL to GitHub PR #${prNumber}...`)

  const repo = resolveRepo()
  if (!repo) fail('Failed to resolve GitHub owner/repo from AWS_CLONE_URL/git remote.')

  const jwt = buildJwt()
  const installation = await githubApi(`https://api.github.com/repos/${repo}/installation`, {
    headers: { Authorization: `Bearer ${jwt}` },
  })
  const token = await githubApi(`https://api.github.com/app/installations/${installation.id}/access_tokens`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${jwt}` },
  })
  // Distinct from Amplify's default amplifyapp.com comment.
  await githubApi(`https://api.github.com/repos/${repo}/issues/${prNumber}/comments`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${token.token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ body: `✅ Preview (custom domain): ${previewUrl}` }),
  })
  console.log(`Posted custom-domain preview URL to PR #${prNumber}`)
}

const postJiraComment = async (previewUrl, branch, label) => {
  const pattern = env.ISSUE_KEY_PATTERN || ''
  const match = pattern ? branch.match(new RegExp(pattern, 'i')) : null
  const issueKey = match ? match[0] : ''
  if (!issueKey) {
    console.warn(`No issue key found in branch name '${branch}' matching pattern '${pattern}'. Skipping Jira comment.`)
    return
  }
  const suffix = label === 'prototype' ? ` for prototype branch ${branch}` : ''
  console.log(`Posting preview URL to Jira issue ${issueKey}${suffix}...`)
  const res = await fetch(`${env.ATLASSIAN_URL}/rest/api/2/issue/${issueKey}/comment`, {
    method: 'POST',
    headers: { Authorization: `Basic ${env.BASE64_AUTH}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ body: previewUrl }),
  })
  if (!res.ok) throw new Error(`Jira comment -> ${res.status}: ${await res.text()}`)
}

;(async () => {
  console.log('Running post-build commands...')

  await postGithubComment()

  // Jira comment for a pull-request preview (source feature branch).
  if (env.AWS_PULL_REQUEST_SOURCE_BRANCH) {
    const previewUrl = `https://pr-${env.AWS_PULL_REQUEST_ID || ''}.${CUSTOM_DOMAIN}/${APP_BASE_PATH}`
    await postJiraComment(previewUrl, env.AWS_PULL_REQUEST_SOURCE_BRANCH, 'pull-request')
  } else {
    console.warn('AWS_PULL_REQUEST_SOURCE_BRANCH is not set. Skipping Jira comment.')
  }

  // Jira comment for prototype branches.
  const awsBranch = env.AWS_BRANCH || ''
  if (awsBranch.startsWith('prototype-')) {
    const previewUrl = `https://${awsBranch}.${CUSTOM_DOMAIN}/${APP_BASE_PATH}`
    await postJiraComment(previewUrl, awsBranch, 'prototype')
  } else {
    console.warn('AWS_BRANCH is not a prototype branch. Skipping prototype Jira comment.')
  }
})().catch((err) => {
  console.error(err.message || err)
  process.exit(1)
})
