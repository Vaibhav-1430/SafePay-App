function clamp(value, min = 0, max = 1) {
  return Math.max(min, Math.min(max, value));
}

function avg(values = []) {
  const valid = values.filter((v) => typeof v === 'number' && v > 0);
  if (valid.length === 0) return 0;
  return valid.reduce((sum, v) => sum + v, 0) / valid.length;
}

function classify(score) {
  if (score >= 0.75) return 'High Risk';
  if (score >= 0.4) return 'Medium Risk';
  return 'Safe';
}

function analyzeTransaction(payload) {
  const {
    amount,
    known_receiver: knownReceiver = false,
    tx_count_last_24h: txCountLast24h = 0,
    unusual_spending_pattern: unusualSpendingPattern = false,
    historical_amounts: historicalAmounts = [],
    is_new_merchant: isNewMerchant = false,
    tx_hour: txHour,
  } = payload;

  let score = 0.08;
  const triggers = [];

  if (amount >= 5000) {
    score += 0.2;
    triggers.push('Unusually high amount');
  }
  if (isNewMerchant || !knownReceiver) {
    score += 0.2;
    triggers.push('New merchant or unknown receiver');
  }
  if (txCountLast24h >= 8) {
    score += 0.18;
    triggers.push('Rapid transaction frequency');
  }
  if (unusualSpendingPattern) {
    score += 0.15;
    triggers.push('Unusual spending pattern');
  }

  const hour = typeof txHour === 'number' ? txHour : new Date().getHours();
  if (hour < 5 || hour > 23) {
    score += 0.12;
    triggers.push('Unusual transaction time');
  }

  const historicalAvg = avg(historicalAmounts);
  if (historicalAvg > 0 && amount > historicalAvg * 2.5) {
    score += 0.14;
    triggers.push('Amount is significantly above historical average');
  }

  const riskScore = clamp(score);
  const classification = classify(riskScore);

  return {
    risk_score: riskScore,
    classification,
    triggers,
    require_extra_verification: classification === 'High Risk',
    delay_recommended: classification === 'High Risk' && amount >= 7000,
  };
}

function securityCheck(payload) {
  const tx = analyzeTransaction(payload);
  const safetyScore = clamp(1 - tx.risk_score);

  return {
    safe: safetyScore >= 0.5,
    safety_score: safetyScore,
    risk: tx,
    recommendation:
      safetyScore >= 0.75
        ? 'Proceed normally.'
        : safetyScore >= 0.5
          ? 'Proceed with verification.'
          : 'Block and require additional verification.',
  };
}

module.exports = {
  analyzeTransaction,
  securityCheck,
};
