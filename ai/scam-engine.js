const SCAM_PATTERNS = [
  'send money to unlock parcel',
  'urgent payment required',
  'your account will be blocked',
  'verify kyc now',
  'refund processing fee',
  'click this payment link',
  'otp share now',
  'account suspended',
  'pay now to avoid block',
];

function clamp(v, min = 0, max = 1) {
  return Math.max(min, Math.min(max, v));
}

function detectScamMessage(message) {
  const text = String(message || '').trim().toLowerCase();
  if (!text) {
    return {
      scam_probability: 0,
      is_scam: false,
      matched_patterns: [],
      warning: 'No suspicious language found.',
    };
  }

  const matched = SCAM_PATTERNS.filter((p) => text.includes(p));
  let score = matched.length > 0 ? 0.84 : 0.08;

  if (/(urgent|immediately|now|blocked|suspended|otp|link)/.test(text)) {
    score += 0.2;
  }
  if (/(pay|send|transfer).*(fee|charge|unlock|verify)/.test(text)) {
    score += 0.15;
  }

  const scamProbability = clamp(score);
  const isScam = scamProbability >= 0.6;

  return {
    scam_probability: scamProbability,
    is_scam: isScam,
    matched_patterns: matched,
    warning: isScam
      ? 'Warning: This message appears similar to known payment scams.'
      : 'Message appears safe, but always verify sender identity.',
  };
}

module.exports = {
  detectScamMessage,
};
