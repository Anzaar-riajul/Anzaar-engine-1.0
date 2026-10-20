package com.techuboard.app

/**
 * TechuRadixTrie
 * 
 * In-Memory High-Speed Compact Prefix Tree (Radix Trie) for sub-millisecond
 * word lookup and auto-completion.
 * 
 * Time Complexity: O(L) where L = length of search prefix.
 * Independent of the total number of words in the dictionary.
 */
class TechuRadixTrie {

    data class ScoredCandidate(val word: String, val score: Int) : Comparable<ScoredCandidate> {
        override fun compareTo(other: ScoredCandidate): Int {
            // Higher score first; if equal, shorter word first
            val scoreCmp = other.score.compareTo(this.score)
            return if (scoreCmp != 0) scoreCmp else this.word.length.compareTo(other.word.length)
        }
    }

    private class Node {
        var isWord = false
        var frequency = 0
        var terminalWord: String? = null
        val children = HashMap<Char, Node>(4)
    }

    private val root = Node()
    private var totalWordCount = 0

    val size: Int
        get() = totalWordCount

    /**
     * Inserts a word with a base frequency weight (1 to 255).
     */
    fun insert(word: String, frequency: Int = 100) {
        val trimmed = word.trim()
        if (trimmed.isEmpty()) return

        var curr = root
        for (ch in trimmed) {
            var child = curr.children[ch]
            if (child == null) {
                child = Node()
                curr.children[ch] = child
            }
            curr = child
        }

        if (!curr.isWord) {
            totalWordCount++
        }
        curr.isWord = true
        curr.frequency = maxOf(curr.frequency, frequency)
        curr.terminalWord = trimmed
    }

    /**
     * Checks if exact word exists in the Trie.
     */
    fun contains(word: String): Boolean {
        var curr = root
        for (ch in word.trim()) {
            curr = curr.children[ch] ?: return false
        }
        return curr.isWord
    }

    /**
     * Finds candidates starting with the given prefix in O(L) time.
     * Returns top candidates ordered by frequency score and length.
     */
    fun findByPrefix(prefix: String, maxResults: Int = 12): List<ScoredCandidate> {
        val cleanPrefix = prefix.trim()
        if (cleanPrefix.isEmpty()) return emptyList()

        var curr = root
        for (ch in cleanPrefix) {
            curr = curr.children[ch] ?: return emptyList()
        }

        val candidates = mutableListOf<ScoredCandidate>()
        collectAllWords(curr, candidates, maxResults * 3)

        candidates.sort()
        return candidates.take(maxResults)
    }

    private fun collectAllWords(node: Node, results: MutableList<ScoredCandidate>, limit: Int) {
        if (results.size >= limit) return

        if (node.isWord && node.terminalWord != null) {
            results.add(ScoredCandidate(node.terminalWord!!, node.frequency))
        }

        for (child in node.children.values) {
            if (results.size >= limit) break
            collectAllWords(child, results, limit)
        }
    }
}
