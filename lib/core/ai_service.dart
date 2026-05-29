class AIService {
  // This will handle checking the AI's response status
  static String getAIStatusText(String status) {
    switch (status) {
      case 'pending':
        return 'AI Agent is triaging...';
      case 'completed':
        return 'Prioritized by SafeWatch AI';
      case 'failed':
        return 'Manual Triage Required';
      default:
        return 'Processing...';
    }
  }
}
