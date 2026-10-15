import Cocoa
import os.log

class TablePreviewVC: NSViewController, PreviewVC {
	let headers: [String]
	let cells: [[String]]
	let pageSize = 100
	private(set) var currentPage = 0
	var pageCount: Int {
		max(1, (cells.count + pageSize - 1) / pageSize)
	}

	var displayedRows: [[String]] {
		let start = currentPage * pageSize
		let end = min(start + pageSize, cells.count)
		return orderedRowIndices[start ..< end].map { cells[$0] }
	}

	private var orderedRowIndices: [Int]
	private let rowCountLabel = NSTextField(labelWithString: "")
	private let previousButton = NSButton(title: "Previous", target: nil, action: nil)
	private let nextButton = NSButton(title: "Next", target: nil, action: nil)

	@IBOutlet private var tableView: NSTableView!

	required convenience init(headers: [String], cells: [[String]]) {
		self.init(nibName: nil, bundle: nil, headers: headers, cells: cells)
	}

	init(
		nibName nibNameOrNil: NSNib.Name?,
		bundle nibBundleOrNil: Bundle?,
		headers: [String],
		cells: [[String]]
	) {
		self.headers = headers
		self.cells = cells
		orderedRowIndices = Array(cells.indices)
		super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
	}

	@available(*, unavailable)
	required init?(coder _: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		setUpView()
		deleteDefaultColumns()
		createColumns()
		createPaginationFooter()
		updatePage()
	}

	private func setUpView() {
		tableView.delegate = self
		tableView.dataSource = self
	}

	/// Deletes all columns created by default using Interface Builder.
	private func deleteDefaultColumns() {
		while !tableView.tableColumns.isEmpty {
			if let column = tableView.tableColumns.first {
				tableView.removeTableColumn(column)
			}
		}
	}

	/// Creates table columns for all headers.
	private func createColumns() {
		for (index, header) in headers.enumerated() {
			let columnID = NSUserInterfaceItemIdentifier(rawValue: String(index))
			let column = NSTableColumn(identifier: columnID)
			column.title = header
			column.sortDescriptorPrototype = NSSortDescriptor(key: String(index), ascending: true)
			column.minWidth = 50
			column.maxWidth = 500
			tableView.addTableColumn(column)
		}
	}

	private func createPaginationFooter() {
		guard let scrollView = tableView.enclosingScrollView else {
			return
		}
		let footer = NSBox()
		footer.boxType = .custom
		footer.borderWidth = 0
		footer.fillColor = .windowBackgroundColor
		footer.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(footer)

		let bottomConstraints = view.constraints.filter {
			$0.firstAttribute == .bottom && $0.secondAttribute == .bottom &&
				($0.firstItem as? NSView === scrollView || $0.secondItem as? NSView === scrollView)
		}
		NSLayoutConstraint.deactivate(bottomConstraints)
		NSLayoutConstraint.activate([
			scrollView.bottomAnchor.constraint(equalTo: footer.topAnchor),
			footer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			footer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			footer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
			footer.heightAnchor.constraint(equalToConstant: 42),
		])

		rowCountLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
		rowCountLabel.textColor = .secondaryLabelColor
		rowCountLabel.lineBreakMode = .byTruncatingTail
		previousButton.target = self
		previousButton.action = #selector(showPreviousPage(_:))
		nextButton.target = self
		nextButton.action = #selector(showNextPage(_:))
		let spacer = NSView()
		spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
		let stack = NSStackView(views: [rowCountLabel, spacer, previousButton, nextButton])
		stack.orientation = .horizontal
		stack.spacing = 8
		stack.translatesAutoresizingMaskIntoConstraints = false
		footer.addSubview(stack)
		NSLayoutConstraint.activate([
			stack.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 12),
			stack.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -12),
			stack.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
		])
	}

	func applySort(columnIndex: Int, ascending: Bool) {
		guard headers.indices.contains(columnIndex) else {
			return
		}
		orderedRowIndices.sort { firstIndex, secondIndex in
			let first = columnIndex < cells[firstIndex].count ? cells[firstIndex][columnIndex] : ""
			let second = columnIndex < cells[secondIndex]
				.count ? cells[secondIndex][columnIndex] : ""
			let firstValue = first.trimmingCharacters(in: .whitespacesAndNewlines)
			let secondValue = second.trimmingCharacters(in: .whitespacesAndNewlines)
			if firstValue.isEmpty || secondValue.isEmpty {
				if firstValue.isEmpty != secondValue.isEmpty {
					return !firstValue.isEmpty
				}
				return firstIndex < secondIndex
			}
			let firstNumber = Double(firstValue).flatMap { $0.isFinite ? $0 : nil }
			let secondNumber = Double(secondValue).flatMap { $0.isFinite ? $0 : nil }
			let comparison: ComparisonResult
			switch (firstNumber, secondNumber) {
				case let (firstNumber?, secondNumber?):
					comparison = firstNumber == secondNumber ? .orderedSame :
						(firstNumber < secondNumber ? .orderedAscending : .orderedDescending)
				case (nil, nil):
					comparison = firstValue.compare(
						secondValue,
						options: [.caseInsensitive, .numeric]
					)
				case (_?, nil):
					comparison = .orderedAscending
				case (nil, _?):
					comparison = .orderedDescending
			}
			if comparison == .orderedSame {
				return firstIndex < secondIndex
			}
			return ascending ? comparison == .orderedAscending : comparison == .orderedDescending
		}
		currentPage = 0
		if isViewLoaded { updatePage() }
	}

	func previousPage() {
		guard currentPage > 0 else {
			return
		}
		currentPage -= 1
		if isViewLoaded { updatePage() }
	}

	func nextPage() {
		guard currentPage + 1 < pageCount else {
			return
		}
		currentPage += 1
		if isViewLoaded { updatePage() }
	}

	@objc
	private func showPreviousPage(_: NSButton) {
		previousPage()
	}

	@objc
	private func showNextPage(_: NSButton) {
		nextPage()
	}

	private func updatePage() {
		let start = currentPage * pageSize
		let end = min(start + pageSize, cells.count)
		let rowRange = cells.isEmpty ? "0 rows" : "Rows \(start + 1)–\(end) of \(cells.count)"
		rowCountLabel.stringValue = "\(rowRange) · Page \(currentPage + 1) of \(pageCount)"
		previousButton.isEnabled = currentPage > 0
		nextButton.isEnabled = currentPage + 1 < pageCount
		tableView.reloadData()
		if tableView.numberOfRows > 0 { tableView.scrollRowToVisible(0) }
	}
}

extension TablePreviewVC: NSTableViewDataSource, NSTableViewDelegate {
	func numberOfRows(in _: NSTableView) -> Int {
		min(pageSize, max(0, cells.count - currentPage * pageSize))
	}

	func tableView(_ tableView: NSTableView, sortDescriptorsDidChange _: [NSSortDescriptor]) {
		guard let descriptor = tableView.sortDescriptors.first,
		      let key = descriptor.key,
		      let columnIndex = Int(key)
		else { return }
		applySort(columnIndex: columnIndex, ascending: descriptor.ascending)
	}

	/// Fills the table with the `tableData`.
	func tableView(
		_: NSTableView,
		viewFor tableColumn: NSTableColumn?,
		row rowIndex: Int
	) -> NSView? {
		let row = cells[orderedRowIndices[currentPage * pageSize + rowIndex]]
		guard let identifier = tableColumn?.identifier.rawValue,
		      let columnIndex = Int(identifier)
		else {
			return nil
		}
		let cellValue = columnIndex < row.count ? row[columnIndex] : ""

		let textField = NSTextField()
		textField.stringValue = cellValue
		textField.isEditable = false
		textField.isSelectable = true
		textField.isBordered = false
		textField.drawsBackground = false
		textField.lineBreakMode = .byTruncatingTail

		return textField
	}
}
